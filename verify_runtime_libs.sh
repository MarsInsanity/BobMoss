#!/bin/bash

# Stop the build when the image lacks a shared library that something on it, or
# spruce on TF2, loads at runtime. cleanup_filesystem.sh removes every build-only
# package; this is what proves that took nothing a program needs with it. See
# scripts/ci/verify-runtime-libs.py for what is checked.

echo -e "Verifying runtime libraries...\n\n"
_verify_args=""
[[ "${BUILD_ARMHF}" == "y" ]] && _verify_args="--armhf"
if ! sudo python3 -I scripts/ci/verify-runtime-libs.py Arkbuild ${_verify_args}; then
  echo "Runtime library check failed. A library that a removed package used to pull in is gone:"
  echo "name the package that provides it in needed_packages.txt (or needed_packages32.txt for armhf)."
  exit 1
fi

# What the image carries, for the build log.
sudo chroot Arkbuild/ dpkg-query -W -f '${db:Status-Status} ${Installed-Size} ${Package}:${Architecture}\n' \
  | awk '$1 == "installed" { n++; kb += $2; print $2, $3 } END { printf "%d packages, %d MB installed\n", n, kb / 1024 > "/dev/stderr" }' \
  | sort -rn | head -n 25 | awk '{ printf "  %6.1f MB  %s\n", $1 / 1024, $2 }'
