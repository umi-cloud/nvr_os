#!/bin/bash
# 在 bookworm arm64 chroot 里依次打 mpp → librga → gst-rockchip 三个包,产物落 /out
set -e
export DEB_BUILD_OPTIONS="parallel=8 nocheck"
mkdir -p /out
cd /build/mpp && dpkg-buildpackage -us -uc -b -j8 > /out/mpp.build.log 2>&1 && echo "mpp OK" || { tail -30 /out/mpp.build.log; exit 1; }
dpkg -i /build/librockchip-mpp1_*.deb /build/librockchip-vpu0_*.deb /build/librockchip-mpp-dev_*.deb > /dev/null
cd /build/librga-pkg && dpkg-buildpackage -us -uc -b > /out/librga.build.log 2>&1 && echo "librga OK" || { tail -30 /out/librga.build.log; exit 1; }
dpkg -i /build/librga2_*.deb /build/librga-dev_*.deb > /dev/null
cd /build/gst-rockchip-src && dpkg-buildpackage -us -uc -b -j8 > /out/gst.build.log 2>&1 && echo "gst-rockchip OK" || { tail -30 /out/gst.build.log; exit 1; }
cp /build/*.deb /out/
ls -l /out/*.deb | awk '{print $5, $9}'
