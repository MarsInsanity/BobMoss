# BobMoss: dArkMoss for the R36S clone (G80CA-MB)

This repository is [spruceUI/dArkMoss](https://github.com/spruceUI/dArkMoss)
plus one extra unit, `r36sclone`, on branch `g80ca`. Everything else is
upstream's, unchanged; see [README.md](README.md) for dArkMoss itself.

Build it with `make r36sclone`. In GitHub Actions, put the new version in
`.github/g80ca-version` on branch `g80ca` and push: the **g80ca release**
workflow (`.github/workflows/g80ca-release.yaml`) builds it and publishes it.

## Releases

This repository's releases serve several handhelds, so the G80CA's are told
apart by their tag:

- `g80ca`: the newest G80CA build. There is always exactly one.
- `g80ca-YYYY-MM-DD`: every older G80CA build, by the day it was built
  (`-2`, `-3`... for a second build the same day).

An installer can pick the G80CA's builds, or skip them, by tag alone. The
g80ca release workflow runs upstream's build-all for `r36sclone` (or waits for
one already running), then moves the previous `g80ca` release to its dated
tag and the new `beta-g80ca` prerelease to `g80ca`. When the version in
`.github/g80ca-version` is already built, it only re-tags.

The tag `g80ca` and the branch `g80ca` share a name, so name the branch in
full where git could take either: `git push origin HEAD:refs/heads/g80ca`,
and `refs/heads/g80ca` as the ref when starting a workflow by hand.

## How the clone stays out of upstream's files

Apart from two registrations CI needs (`r36sclone` in `.github/units.txt` and
its target in `Makefile`), no upstream file is edited in git. Everything for
the clone is in files of its own:

| Path | What |
| --- | --- |
| `build_r36sclone.sh` | The build: applies `patches/r36sclone/build/*.patch`, then runs upstream's `build_g350.sh` with `UNIT=r36sclone`, then takes the patches back out. |
| `patches/r36sclone/build/` | The clone's additions to the shared build scripts (`build_kernel.sh`, `image_setup.sh`, `finishing_touches.sh`, `setup_spruce_handoff.sh`, `build_update.sh`, `scripts/spruce/dmupd-apply.sh`, `scripts/00-header`), applied only while the clone builds. `0002` is a general fix (game saves on power-off) kept for this unit. |
| `patches/r36sclone/kernel/series/` | Kernel: the board's two dts and lcdyk0517's joypad driver. |
| `patches/r36sclone/uboot/` | U-Boot: the G80CA board dts and its two panels. |
| `scripts/r36sclone/` | `hpjackd`, the headphone switch. |
| `logos/r36sclone/` | Boot logos (drawn with `patches/r36sclone/make-logo.patch`). |
| `extras/spruce/App/USBMode/` | spruce app: OTG port as WiFi host or wired adbd. |
| `.github/workflows/g80ca-release.yaml`, `.github/g80ca-version` | Builds and publishes under the `g80ca` tags (see Releases). |
| `.github/upstream-sync.json` | What the daily upstream check last reviewed. |

## Keeping up with upstream

Merge upstream with `git merge upstream/spruce`. Because upstream's files are
not edited here, the merge is clean. If upstream changed lines that a
`patches/r36sclone/build` patch touches, the merge is still clean but the
patch no longer applies, and `build_r36sclone.sh` stops at once with
"does not apply". Refresh it in its own commit after the merge:

```sh
git apply --3way patches/r36sclone/build/0001-r36sclone-build-scripts.patch
# resolve, keeping upstream's new lines and re-adding the clone's
{ sed -n '1,/^diff --git/p' patches/r36sclone/build/0001-r36sclone-build-scripts.patch | sed '$d'
  git diff -- build_kernel.sh image_setup.sh finishing_touches.sh setup_spruce_handoff.sh \
              build_update.sh scripts/spruce/dmupd-apply.sh scripts/00-header
} > /tmp/0001.patch && mv /tmp/0001.patch patches/r36sclone/build/0001-r36sclone-build-scripts.patch
git checkout -- build_kernel.sh image_setup.sh finishing_touches.sh setup_spruce_handoff.sh \
                build_update.sh scripts/spruce/dmupd-apply.sh scripts/00-header
```

`git diff upstream/spruce g80ca --stat` should only ever list the clone's own
files plus `.github/units.txt` and `Makefile`.

## The clone

For the R36S clones on the G80CA-MB board (V1.2/V1.3 on the silkscreen), not
the genuine R36S. spruce has no R36S platform and will not get one, so the
image runs spruce's own G350 profile: same SoC, panel size, sticks, joypad
driver and button codes. Nothing on the spruce card changes.

- Kernel: `patches/r36sclone/kernel/series`, applied to christianhaitian's
  rg351 like the Mini M's: the board's two dts, one per panel, and
  lcdyk0517's odroidgo3-joypad, which reads the clone's
  `amux-channel-mapping`. Both from lcdyk0517/arkos.bsp.4.4 (arkos4clone's
  "R36S Clone Type2"); the patches list what was changed.
- U-Boot: `patches/r36sclone/uboot`, the G80CA U-Boot dtb dArkOSRE-R36 ships as
  tested, as source, with both panels for the panel-ID check. U-Boot reads this
  board as an RG351V, so it is loaded as `uboot.dtb` (the `uboot-dtb` opt-in).
- Panels: G80CA units have "Panel 8" (ST7703) or "Panel 9" (NV3051D family).
  U-Boot starts on Panel 8 and switches when the screen answers with Panel 9's
  ID; boot.ini loads the kernel dtb for whichever it ended on. The IDs are the
  ones the G350's panels of the same families answer and have not been read on
  a G80CA, so BOOT also carries `uboot-panel9.dtb`, the same dtb starting on
  Panel 9, and `R36S-PANEL.txt` says how to swap it in.
- Updates: spruce's Firmware Update looks up the G350's payload, which would
  leave the clone dark, so the image stamps `OS_VERSION="999.0.0"` (spruce then
  never offers one) and the real version as `DARKMOSS_VERSION`. Its own payload
  is `dArkMoss_R36SCLONE_<version>.dmupd`: renamed
  `dArkMoss_G350_<version>.dmupd` at the root of the spruce card, Firmware
  Update installs it. The applier checks `DARKMOSS_UNIT`, so it refuses a
  payload built for another unit.
- USB: the clone's only USB data port is the OTG controller, so the image
  leaves wired adbd off and the port stays a host for a WiFi dongle.
  `extras/spruce/App/USBMode` is a spruce app that switches it: copy the
  folder to `App/` on the spruce card, and its menu entry turns adbd at boot
  on (wired adb) or off (WiFi dongle). The boot line carries
  `usbcore.autosuspend=-1`: with autosuspend on, a dongle plugged in after
  boot is not detected.
- Headphones: `hpjackd` sets the rk817 Playback Path to HP while the jack
  switch is on and SPK while it is off. The dts reads the detect pin active
  high, as on the unit this branch is for (dArkOSRE's 20250422 dtb; its
  20250423 dtb and arkos4clone have it active low). On a board that reads it
  the other way, `/boot/headphones-invert` flips it; `R36S-PANEL.txt` says so.
