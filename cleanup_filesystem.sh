#!/bin/bash

# Cleanup to reduce image size and remove build remnants
echo -e "Cleaning up filesystem"
call_chroot "rm -rf /home/ark/EmulationStation-fcamod"
call_chroot "rm -rf /home/ark/libgo2"
call_chroot "rm -rf /home/ark/linux-rga"
call_chroot "rm -rf /home/ark/${CHIPSET}_core_builds"
call_chroot "rm -rf /meson /usr/bin/meson"

# Remove what only the build needed: everything in needed_dev_packages.txt, plus
# what build_deps.sh (gcc-12/g++-12) and build_bluealsa.sh (autotools, docutils)
# install on their own. Upstream removed a hand-kept list here and then
# reinstalled needed_packages.txt, which carried cmake, libsdl2-dev, libtool,
# rustc and ccache - so most of the toolchain (clang/llvm, rust, gcc, ~100 -dev
# packages) came straight back and shipped in the image.
#
# Anything a runtime list also names is kept, and the list is cut down to what
# is installed: apt refuses the whole command over one name it cannot find.
#
# build-essential's own set is named too: apt Suggests dpkg-dev, and autoremove
# keeps whatever an installed package suggests, so dpkg-dev, and the gcc it
# recommends, outlived build-essential.
#
# Two runtime leftovers go the same way, both only Recommends of what stays:
# Mesa's Vulkan drivers (from ffmpeg's libplacebo; every unit renders through
# the Mali blob, and rk3566 ships the Mali Vulkan ICD and deletes Mesa's ICD
# files below anyway) and pocketsphinx's English model (ffmpeg's speech filter).
BUILD_ONLY_PACKAGES=( gcc-12 g++-12 cpp-12 autoconf automake python3-docutils
  dpkg-dev gcc g++ make libc6-dev mesa-vulkan-drivers pocketsphinx-en-us )
while read -r BUILD_ONLY_PACKAGE; do
  [[ -z "$BUILD_ONLY_PACKAGE" || "$BUILD_ONLY_PACKAGE" =~ ^# ]] && continue
  BUILD_ONLY_PACKAGES+=( "$BUILD_ONLY_PACKAGE" )
done <needed_dev_packages.txt
RUNTIME_PACKAGES="$(cat needed_packages.txt bluetooth_needed_packages.txt | grep -v '^#')"
INSTALLED_PACKAGES="$(sudo chroot Arkbuild/ dpkg-query -W -f '${db:Status-Status} ${Package}\n' | awk '$1 == "installed" {print $2}' | sort -u)"
REMOVE_PACKAGES=()
for BUILD_ONLY_PACKAGE in "${BUILD_ONLY_PACKAGES[@]}"; do
  grep -qxF "$BUILD_ONLY_PACKAGE" <<<"$RUNTIME_PACKAGES" && continue
  grep -qxF "$BUILD_ONLY_PACKAGE" <<<"$INSTALLED_PACKAGES" && REMOVE_PACKAGES+=( "$BUILD_ONLY_PACKAGE" )
done
if [ ${#REMOVE_PACKAGES[@]} -gt 0 ]; then
  echo "Removing build-only packages: ${REMOVE_PACKAGES[*]}"
  call_chroot "DEBIAN_FRONTEND=noninteractive apt-get -y purge ${REMOVE_PACKAGES[*]}"
fi
# Suggests are not a reason to keep a package here: nothing on this image is
# installed for what another package merely suggests.
call_chroot "DEBIAN_FRONTEND=noninteractive apt-get -y -o APT::AutoRemove::SuggestsImportant=false autoremove --purge"
call_chroot "apt -y clean"

if [[ "${BUILD_ARMHF}" == "y" ]]; then
  # Ensure additional needed packages are still in place
  while read NEEDED_PACKAGE; do
    if [[ -n "$NEEDED_PACKAGE" ]] && [[ ! "$NEEDED_PACKAGE" =~ ^# ]]; then
      install_package armhf ${NEEDED_PACKAGE}
    fi
  done <needed_packages32.txt
  sync Arkbuild
fi

# Anything the purge above took with it comes back here. upstream skipped
# ffmpeg on rk3566 and held it, for its own ffmpeg build (build_ffmpeg.sh),
# which dArkMoss does not run: Debian's ffmpeg is the one in the image.
while read NEEDED_PACKAGE; do
  if [[ -n "$NEEDED_PACKAGE" ]] && [[ ! "$NEEDED_PACKAGE" =~ ^# ]]; then
    install_package 64 ${NEEDED_PACKAGE}
    protect_package 64 ${NEEDED_PACKAGE}
  fi
done <needed_packages.txt
sync

if [[ "$BUILD_BLUEALSA" == "y" ]]; then
  while read BLUETOOTH_NEEDED_PACKAGE; do
    if [[ -n "$BLUETOOTH_NEEDED_PACKAGE" ]] && [[ ! "$BLUETOOTH_NEEDED_PACKAGE" =~ ^# ]]; then
      install_package 64 ${BLUETOOTH_NEEDED_PACKAGE}
      protect_package 64 ${BLUETOOTH_NEEDED_PACKAGE}
    fi
  done <bluetooth_needed_packages.txt
  call_chroot "systemctl disable watchforbtaudio bluetooth bluealsa"
fi

if [[ "${BUILD_ARMHF}" == "y" ]]; then
  cd Arkbuild/usr/lib/arm-linux-gnueabihf
  for LIB in libEGL.so libEGL.so.1 libEGL.so.1.1.0 libGLES_CM.so libGLES_CM.so.1 libGLESv1_CM.so libGLESv1_CM.so.1 libGLESv1_CM.so.1.1.0 libGLESv2.so libGLESv2.so.2 libGLESv2.so.2.0.0 libGLESv2.so.2.1.0 libGLESv3.so libGLESv3.so.3 libgbm.so libgbm.so.1 libgbm.so.1.0.0 libmali.so libmali.so.1 libMaliOpenCL.so
  do
    sudo rm -fv ${LIB}
    sudo ln -sfv libMali.so ${LIB}
  done
  cd ../../../../

  # We need to replace the armhf version of libasound2t64 with the older libasound2 binary from Bookworm
  # because the current one supplied wtih Trixie has a ioctl error issue which leads to no audio for 32bit apps
  # This can be retrieved from snapshot.debian.org
  for (( ; ; ))
  do
    wget -t 3 -T 60 --no-check-certificate https://snapshot.debian.org/archive/debian/20230104T090216Z/pool/main/a/alsa-lib/libasound2_1.2.8-1%2Bb1_armhf.deb
    if [ $? == 0 ]; then
     break
    fi
	sleep 10
  done
  dpkg --fsys-tarfile libasound2_1.2.8-1+b1_armhf.deb | tar -xO ./usr/lib/arm-linux-gnueabihf/libasound.so.2.0.0 > libasound.so.2.0.0
  sudo mv -f libasound.so.2.0.0 Arkbuild/usr/lib/arm-linux-gnueabihf/
  call_chroot "chown root:root /usr/lib/arm-linux-gnueabihf/libasound.so.2.0.0"
  rm -f libasound2_1.2.8-1+b1_armhf.deb
fi

# libwayland-egl.so{,.1,.1.0.0} are deliberately NOT in this list. Upstream
# symlinks them to libMali.so like the rest, but the blob does not export the
# wayland-egl API - libSDL2 links it, so every binary using the system SDL2 dies
# at startup with "undefined symbol: wl_egl_window_destroy". PyUI is the only
# thing that survived it, because it bundles its own SDL2. Debian's real
# libwayland-egl.so.1.23.1 was on disk the whole time; only the soname symlink
# was being hijacked. Verified on hardware: restore it and system SDL2 loads.
MALI_LIBS="libEGL.so libEGL.so.1 libEGL.so.1.1.0 libGLES_CM.so libGLES_CM.so.1 libGLESv1_CM.so libGLESv1_CM.so.1 libGLESv1_CM.so.1.1.0 libGLESv2.so libGLESv2.so.2 libGLESv2.so.2.0.0 libGLESv2.so.2.1.0 libGLESv3.so libGLESv3.so.3 libgbm.so libgbm.so.1 libgbm.so.1.0.0 libmali.so libmali.so.1 libMaliOpenCL.so"

# Divert the dpkg-owned names before overwriting them with Mali symlinks.
#
# Several of these files belong to real packages - libEGL.so.1 to libegl1,
# libgbm.so.1 to libgbm1, and so on. Replacing them with symlinks and leaving
# no diversion means any later apt operation that reinstalls or upgrades those
# packages silently restores the Mesa files on top, and the GLES stack is gone:
# the Mali blob is the only real GL path on this kernel (there is no panfrost
# driver, so Mesa can only reach llvmpipe). The failure is invisible until
# something tries to make a window.
#
# A diversion makes dpkg write the package's copy to <name>.distrib instead, so
# the symlink survives. Ask dpkg which names it actually owns rather than
# hardcoding the list - it moves between Debian releases.
call_chroot "
  for LIB in ${MALI_LIBS}; do
    TARGET=/usr/lib/aarch64-linux-gnu/\${LIB}
    if dpkg -S \${TARGET} >/dev/null 2>&1; then
      dpkg-divert --divert \${TARGET}.distrib --rename --add \${TARGET} >/dev/null
    fi
  done
"

cd Arkbuild/usr/lib/aarch64-linux-gnu
for LIB in ${MALI_LIBS}
do
  sudo rm -fv ${LIB}
  sudo ln -sfv libMali.so ${LIB}
done
cd ../../../../

# Make sure the built librga shared libs are still available in aarch64
sudo cp -av Arkbuild/usr/lib/librga.so* Arkbuild/usr/lib/aarch64-linux-gnu/


if [[ "${ENABLE_CACHE}" == "y" ]]; then
  sudo rm -f Arkbuild/etc/apt/apt.conf.d/99proxy
  sudo sed -i '/127.0.0.1:3142\//s///' Arkbuild/etc/apt/sources.list
fi

# Point the SDL2 soname at whichever build actually landed in the image.
#
# This used to interpolate ${extension}, which is only ever set in
# build_sdl2.sh and is unset here, so it expanded to nothing and produced
#   libSDL2-2.0.so.0 -> libSDL2.so -> libSDL2-2.0.so.0.
# with the version cut off. The whole chain dangled, and every binary that
# links SDL2 at load time - RetroArch among them - died with "libSDL2-2.0.so.0:
# cannot open shared object file". PyUI hid it by bundling its own copy.
#
# Resolve the real filename by globbing Arkbuild from the host rather than
# inside the chroot: call_chroot embeds its argument in host-side double
# quotes, so any $ in it expands here anyway.
link_sdl2_soname() {
  _libdir="$1"
  _real="$(basename "$(ls Arkbuild${_libdir}/libSDL2-2.0.so.0.*.* 2>/dev/null | head -n 1)" 2>/dev/null)"
  if [ -z "${_real}" ]; then
    echo "WARNING: no libSDL2-2.0.so.0.* under ${_libdir}; leaving SDL2 symlinks alone"
    return
  fi
  call_chroot "ln -sfnv ${_libdir}/${_real} ${_libdir}/libSDL2-2.0.so.0"
  call_chroot "ln -sfnv libSDL2-2.0.so.0 ${_libdir}/libSDL2.so"
}

link_sdl2_soname /usr/lib/aarch64-linux-gnu
if [[ "${BUILD_ARMHF}" == "y" ]]; then
  link_sdl2_soname /usr/lib/arm-linux-gnueabihf
fi
# Ensure sdl2-config is linked to the proper version
call_chroot "ln -sfv /usr/lib/aarch64-linux-gnu/bin/sdl2-config /usr/bin/sdl2-config"
# Upstream re-pointed /lib/libSDL_image-1.2.so.0 here, but the $(find) in that
# line ran on the build host, not in the chroot, and SDL_image 1.2 is not
# installed: it left "ln -sf /lib/libSDL_image-1.2.so.0", a symlink to itself.
call_chroot "rm -f /lib/libSDL_image-1.2.so.0"
call_chroot "ldconfig -X"

if grep -qs "Arkbuild/home/ark/Arkbuild_ccache" /proc/mounts; then
  sudo umount -l Arkbuild/home/ark/Arkbuild_ccache
fi
sudo rm -rf Arkbuild/home/ark/Arkbuild_ccache
# NOT removing /var/log/journal - see setup_spruce_handoff.sh. A
# persistent journal is the difference between debugging this device from a log
# and debugging it by swapping cards, and it is capped at 64M.
sudo rm Arkbuild/usr/sbin/policy-rc.d
sudo rm -f Arkbuild/etc/resolv.conf
sudo rm -f Arkbuild/etc/network/interfaces
sudo rm -rf Arkbuild/usr/share/man/*
#for i in {1..8}; do sudo mkdir -p Arkbuild/usr/share/man/man"$i"; done
sudo rm -rf Arkbuild/var/lib/apt/lists/*
sudo rm -f Arkbuild/var/log/*.log
sudo rm -f Arkbuild/var/log/apt/*.log
sudo rm -f Arkbuild/tmp/reboot-needed
if [[ "${CHIPSET}" == "rk3566" ]]; then
  sudo rm -f Arkbuild/usr/share/vulkan/icd.d/*_icd.*
  # Ensure libvulkan is symlinked properly
  call_chroot "find /usr/lib/aarch64-linux-gnu -type f -name 'libvulkan.so*' -not -name 'libvulkan.so.1.3.274' -delete"
  call_chroot "rm -f /usr/lib/aarch64-linux-gnu/libvulkan.so.1 /usr/lib/aarch64-linux-gnu/libvulkan.so"
  call_chroot "ln -sf /usr/lib/aarch64-linux-gnu/libvulkan.so.1.3.274 /usr/lib/aarch64-linux-gnu/libvulkan.so.1"
  call_chroot "ln -sf /usr/lib/aarch64-linux-gnu/libvulkan.so.1 /usr/lib/aarch64-linux-gnu/libvulkan.so"
fi
