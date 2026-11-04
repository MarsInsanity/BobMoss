#!/bin/bash

# Christian's armhf libraries (SDL2, librga, libgo2) without the RetroArch build
# that normally brings in his 32-bit chroot.

source ./scripts/ci/build-cache.sh

ARM32_LIB_DIR=Arkbuild/usr/lib/arm-linux-gnueabihf
ARM32_CACHE_KEY="$(bc_key utils.sh build_deps.sh build_sdl2.sh build_arm32_libs.sh \
    needed_packages.txt needed_dev_packages.txt "${DEBIAN_CODE_NAME}" "${CHIPSET}" "${UNIT}" \
    "$(bc_remote_sha "https://github.com/christianhaitian/${CHIPSET}_core_builds.git")")"
ARM32_CACHE_ASSET="arm32-libs-${UNIT}-${ARM32_CACHE_KEY}.tar.zst"

if bc_fetch "$ARM32_CACHE_ASSET" arm32-libs.tar.zst && sudo tar --zstd -xpf arm32-libs.tar.zst; then
  echo "armhf libraries restored from build cache."
else
  ( setup_arkbuild32 )
  # Cache only a complete set. setup_arkbuild32 makes the libSDL2 links even
  # when the 32-bit SDL2 build failed, and tar packs dangling links happily:
  # every later run would restore them and fail verify_armhf.sh full below.
  # Checked in the chroot because the links are absolute.
  if sudo chroot Arkbuild/ bash -c "for f in libSDL2-2.0.so.0 librga.so libgo2.so; do [ -e /usr/lib/arm-linux-gnueabihf/\$f ] || exit 1; done" \
      && sudo tar --zstd -cf arm32-libs.tar.zst ${ARM32_LIB_DIR}/libSDL2* ${ARM32_LIB_DIR}/librga.so* ${ARM32_LIB_DIR}/libgo2.so* \
      $(ls Arkbuild/usr/local/share/a10mini/sdl32-* 2>/dev/null); then
    bc_publish "$ARM32_CACHE_ASSET" arm32-libs.tar.zst
  fi
fi
rm -f arm32-libs.tar.zst
sudo chroot Arkbuild/ ldconfig -X
source ./verify_armhf.sh full
