#!/bin/bash
pause()
{
echo "Press any key to quit:"
read -n1 -s key
exit 1
}
echo "start to make update.img..."
if [ ! -f "Image/parameter" -a ! -f "Image/parameter.txt" ]; then
	echo "Error:No found parameter!"
	exit 1
fi
if [ ! -f "package-file" ]; then
	echo "Error:No found package-file!"
	exit 1
fi
./afptool -pack ./ Image/update.img || pause
# 芯片标签从 loader 头部读(同 rv1126b SDK 的 mk-updateimg.sh),不再写死 RK3568:rk3566 读出 RK3568,rv1126b 读出 RK110F
TAG=RK$(dd if=Image/MiniLoaderAll.bin bs=1 count=4 skip=21 status=none | rev)
./rkImageMaker -$TAG Image/MiniLoaderAll.bin Image/update.img update.img -os_type:androidos || pause
echo "Making ./Image/update.img OK."
#echo "Press any key to quit:"
#read -n1 -s key
exit $?
