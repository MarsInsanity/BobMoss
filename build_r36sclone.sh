#!/bin/bash
# R36S clone (G80CA-MB), see R36SCLONE.md: upstream's build_g350.sh with
# UNIT=r36sclone, with patches/r36sclone/build/*.patch applied to the shared
# build scripts for the length of the build. Upstream's files stay unedited in
# git, so merging spruceUI/dArkMoss never conflicts with the clone.
cd "$(dirname "$0")" || exit 1

PATCHES=(patches/r36sclone/build/*.patch)
applied=()
unapply() {
  local i
  for ((i=${#applied[@]}-1; i>=0; i--)); do git apply -R "${applied[i]}"; done
}
for p in "${PATCHES[@]}"; do
  if git apply -R --check "$p" 2>/dev/null; then
    continue  # already in the tree (a previous build stopped before cleaning up)
  fi
  if ! git apply "$p"; then
    echo "ERROR: $p does not apply to this upstream; refresh it (R36SCLONE.md)." >&2
    unapply
    exit 1
  fi
  applied+=("$p")
done
trap unapply EXIT

script="$(mktemp)"
sed -e 's/^export UNIT=g350$/export UNIT=r36sclone/' \
    -e 's/^echo "G350 build completed/echo "R36S clone build completed/' \
    build_g350.sh > "$script"
if ! grep -qx 'export UNIT=r36sclone' "$script"; then
  echo "ERROR: build_g350.sh no longer sets 'export UNIT=g350'; update build_r36sclone.sh." >&2
  rm -f "$script"
  exit 1
fi
bash "$script"
status=$?
rm -f "$script"
exit $status
