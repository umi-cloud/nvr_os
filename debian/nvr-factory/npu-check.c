/*
 * nvr-factory NPU 自检:固定输入连续推理 N 次,要求每次输出逐字节一致且非全零。
 * 用法: npu-check <model.rknn> [loops]
 * 结论一行写 stdout(成功为测量值,失败为原因),退出码 0 = 通过。
 *
 * 只用 rknn_init/query/inputs_set/run/outputs_get 这几个跨 1.x/2.x 稳定的接口,
 * 不依赖 OpenCV(官方 rknn_common_test 要 cv::imread,rootfs 里没有)。
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "rknn_api.h"

static uint64_t fnv1a(uint64_t h, const uint8_t *p, size_t n)
{
	while (n--) {
		h ^= *p++;
		h *= 0x100000001b3ULL;
	}
	return h;
}

static double now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

int main(int argc, char **argv)
{
	rknn_context ctx = 0;
	rknn_input_output_num io;
	rknn_tensor_attr in_attr;
	rknn_input in;
	rknn_output *outs = NULL;
	uint8_t *model = NULL, *data = NULL;
	uint64_t first = 0;
	double total = 0;
	long size;
	int loops, i, j, ret = 1;
	FILE *f;

	if (argc < 2) {
		printf("usage: %s <model.rknn> [loops]\n", argv[0]);
		return 2;
	}
	loops = argc > 2 ? atoi(argv[2]) : 10;

	f = fopen(argv[1], "rb");
	if (!f) {
		printf("cannot open model %s\n", argv[1]);
		return 1;
	}
	fseek(f, 0, SEEK_END);
	size = ftell(f);
	fseek(f, 0, SEEK_SET);
	model = malloc(size);
	if (!model || fread(model, 1, size, f) != (size_t)size) {
		printf("failed to read model\n");
		fclose(f);
		return 1;
	}
	fclose(f);

	if (rknn_init(&ctx, model, size, 0, NULL) != RKNN_SUCC) {
		printf("rknn_init failed (driver or runtime)\n");
		goto out;
	}
	if (rknn_query(ctx, RKNN_QUERY_IN_OUT_NUM, &io, sizeof(io)) != RKNN_SUCC || io.n_input != 1) {
		printf("query in/out num failed\n");
		goto out;
	}
	memset(&in_attr, 0, sizeof(in_attr));
	in_attr.index = 0;
	if (rknn_query(ctx, RKNN_QUERY_INPUT_ATTR, &in_attr, sizeof(in_attr)) != RKNN_SUCC) {
		printf("query input attr failed\n");
		goto out;
	}

	/* 确定性的伪图像:每次运行完全相同,输出也必须完全相同 */
	data = malloc(in_attr.n_elems);
	outs = calloc(io.n_output, sizeof(*outs));
	if (!data || !outs) {
		printf("out of memory\n");
		goto out;
	}
	for (i = 0; i < (int)in_attr.n_elems; i++)
		data[i] = (uint8_t)(i * 31 + (i >> 8));
	memset(&in, 0, sizeof(in));
	in.index = 0;
	in.type = RKNN_TENSOR_UINT8;
	in.fmt = RKNN_TENSOR_NHWC;
	in.size = in_attr.n_elems;
	in.buf = data;

	for (i = 0; i < loops; i++) {
		uint64_t h = 0xcbf29ce484222325ULL;
		int nonzero = 0;
		double t0;

		if (rknn_inputs_set(ctx, 1, &in) != RKNN_SUCC) {
			printf("run %d: set input failed\n", i + 1);
			goto out;
		}
		t0 = now_ms();
		if (rknn_run(ctx, NULL) != RKNN_SUCC) {
			printf("run %d: inference failed\n", i + 1);
			goto out;
		}
		total += now_ms() - t0;

		memset(outs, 0, io.n_output * sizeof(*outs));
		for (j = 0; j < (int)io.n_output; j++)
			outs[j].want_float = 0;
		if (rknn_outputs_get(ctx, io.n_output, outs, NULL) != RKNN_SUCC) {
			printf("run %d: get output failed\n", i + 1);
			goto out;
		}
		for (j = 0; j < (int)io.n_output; j++) {
			const uint8_t *p = outs[j].buf;
			uint32_t k;

			h = fnv1a(h, p, outs[j].size);
			for (k = 0; k < outs[j].size && !nonzero; k++)
				nonzero = p[k] != 0;
		}
		rknn_outputs_release(ctx, io.n_output, outs);

		if (!nonzero) {
			printf("run %d: output all zero\n", i + 1);
			goto out;
		}
		if (i == 0)
			first = h;
		else if (h != first) {
			printf("run %d: output differs from run 1\n", i + 1);
			goto out;
		}
	}
	printf("%d runs identical, hash %016llx, avg %.1fms\n",
	       loops, (unsigned long long)first, total / loops);
	ret = 0;
out:
	if (ctx)
		rknn_destroy(ctx);
	free(outs);
	free(data);
	free(model);
	return ret;
}
