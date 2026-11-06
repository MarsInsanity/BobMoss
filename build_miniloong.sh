#!/bin/bash
#exec 3>&1 4>&2
#trap 'exec 2>&4 1>&3' 0 1 2 3
#exec 1>build.log 2>&1
#set -e
if [ -f "build.log" ]; then
  ext=1
  while true
  do
    if [ -f "build.log.${ext}" ]; then
      let ext=ext+1
	  continue
	else
      mv build.log build.log.${ext}
	  break
	fi
  done
fi
(
# Set chipset in environment variable
export CHIPSET=rk3566
export UNIT=miniloong
export UNIT_DTB=${CHIPSET}-${UNIT}

# Load shared utilities (if any)
source ./utils.sh

# Let's make sure necessary tools are available
source ./prepare.sh

# Step-by-step build process
source ./setup_partition-rk3566.sh
source ./bootstrap_rootfs-rk3566.sh
source ./verify_armhf.sh base
source ./build_kernel-rk3566.sh
source ./build_deps.sh

# --- dArkMoss: only the port runtime and the hardware helpers ---------------
# spruce is the frontend and brings RetroArch, the standalone emulators, PICO-8
# and PortMaster on TF2, so the upstream dArkOS emulator and EmulationStation
# builds are gone from this repository. What is left is what spruce, PortMaster
# ports and the hardware need from the base:
#
# dArkOS builds its own SDL2 from christianhaitian/rk3566_core_builds and
# installs it AS the system libSDL2-2.0.so.0. That build is made for this Mali
# blob, and it is what RetroArch, the PPSSPP/Flycast standalones and every
# dArkOS port run against. Stock Debian's SDL2 is not a substitute: it links
# libwayland-egl and asks for a desktop GL config the blob does not advertise.
source ./build_sdl2.sh
if [[ "${BUILD_ARMHF}" == "y" ]]; then
  # 32-bit RetroArch (ra32.universal) and 32-bit ports: armhf SDL2, librga, libgo2.
  source ./build_arm32_libs.sh
fi
# oga_controls is what ArkOS ports call to read the pad.
source ./build_ogacontrols.sh
# gptokeyb maps the pad to keys for ports that want a keyboard; drmtool is
# called by ports that take the display directly and by panel_set.sh.
source ./build_gptokeyb.sh
source ./build_drmtool.sh
# BatteryPlus in pmic mode: the kernel gauge %, smoothed.
source ./build_batteryplus.sh
if [[ "${BUILD_BLUEALSA}" == "y" ]]; then
  source ./build_bluealsa.sh
fi
# --- end dArkMoss ------------------------------------------------------------
source ./finishing_touches-rk3566.sh
source ./setup_spruce_handoff.sh
source ./cleanup_filesystem.sh
source ./verify_armhf.sh full
source ./verify_runtime_libs.sh
source ./build_update.sh
source ./write_rootfs-rk3566.sh
source ./clean_mounts.sh
source ./create_image.sh
) 2>&1 | tee -a build.log

echo "Miniloong Pocket 1 build completed. Final image is ready."
