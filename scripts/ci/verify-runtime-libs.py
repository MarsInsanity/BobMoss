#!/usr/bin/env python3
"""Check that the finished rootfs has every shared library its programs load.

    verify-runtime-libs.py <rootfs> [--armhf]

dpkg keeps its own packages' dependencies whole. What it cannot see is what the
build puts on top of Debian (the SDL2, librga, libgo2 and helper builds, the
Mali blobs, bluez-alsa, the PortMaster compat libraries) and what spruce runs
from TF2 against this base. Removing the build-only packages can take a library
one of those needs with it, and nothing else would notice until a game or a
port failed to start on a device. So:

  1. every ELF program or library in the rootfs that no package owns must find
     each of its DT_NEEDED libraries, by file name or by SONAME (ldconfig makes
     the soname links on first boot), in the system library directories or its
     own RPATH/RUNPATH. A miss fails the build, except for the prebuilt
     PortMaster compat libraries and the Vulkan loader, which only warn;
  2. the libraries spruce's own binaries (RetroArch, the standalone emulators,
     PICO-8, PortMaster's tools, spruce's helpers) load from the base must all
     be there. The list is what their DT_NEEDED entries ask for and spruce does
     not ship itself.

Pure Python, no readelf: it runs on the build host against the chroot, and
resolves symlinks inside the rootfs rather than on the host.
"""
import glob
import os
import re
import struct
import sys

EM_ARM, EM_AARCH64 = 40, 183
ARCH_NAME = {EM_AARCH64: "aarch64", EM_ARM: "armhf"}
TRIPLET = {EM_AARCH64: "aarch64-linux-gnu", EM_ARM: "arm-linux-gnueabihf"}

# What spruce's binaries load from the base, from their DT_NEEDED entries minus
# what spruce ships (spruce/flip/lib and each emulator's own lib dirs).
SPRUCE_NEEDS = {
    EM_AARCH64: """
        ld-linux-aarch64.so.1 libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2
        librt.so.1 libresolv.so.2 libutil.so.1 libgcc_s.so.1 libstdc++.so.6
        libgomp.so.1 libz.so.1 libGLESv2.so.2 libEGL.so.1 libGLESv2.so libEGL.so
        libSDL2-2.0.so.0 libasound.so.2 libfreetype.so.6 libdrm.so.2 libudev.so.1
        libevdev.so.2 libpng16.so.16 libcurl.so.4 libbsd.so.0 libdbus-1.so.3
        libsndfile.so.1 libvorbisenc.so.2 libtheoraenc.so.1 libFLAC.so.8
        libfluidsynth.so.3 libharfbuzz.so.0 libfontconfig.so.1 libglib-2.0.so.0
        libspeexdsp.so.1 libsqlite3.so.0 libexpat.so.1 libffi.so.8 libssl.so.3
        libcrypto.so.3 libtinfo.so.6 libncursesw.so.6 libuuid.so.1
    """.split(),
    # 32-bit RetroArch (ra32.universal) and its cores.
    EM_ARM: """
        ld-linux-armhf.so.3 libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2
        librt.so.1 libgcc_s.so.1 libstdc++.so.6 libz.so.1 libGLESv2.so.2
        libEGL.so.1 libSDL2-2.0.so.0 libasound.so.2 libfreetype.so.6 libudev.so.1
    """.split(),
}

# Prebuilt libraries whose own dependencies this build does not control: a gap
# there is reported, not fatal. fetch_compat_libs.sh's PortMaster compat set and
# the rk3566 Vulkan loader/hook from misc/rk3566/vulkan.
WARN_ONLY = re.compile(
    r"^lib(jpeg\.so\.8|av(codec|format|util|filter|device)\.so\.5\d|"
    r"sw(resample|scale)\.so\.\d|vpx\.so\.[56]|webp\.so\.6|aom\.so\.0|dav1d\.so\.4|"
    r"codec2\.so\.0\.[89].*|wavpack\.so\.1|x26[45]\.so\.1\d\d|FLAC\.so\.8|"
    r"srt-gnutls\.so\.1\.4.*|ssh-gcrypt\.so\.4|vulkan\.so\.1\..*|mali-hook\.so.*)$")

# Not searched for programs: pseudo filesystems, caches, kernel modules and
# firmware (not dynamic ELF), and the build's own leftovers.
SKIP_DIRS = {"proc", "sys", "dev", "run", "tmp", "boot", "var/cache", "var/lib/apt",
             "var/log", "usr/lib/modules", "usr/lib/firmware", "home/ark/Arkbuild_ccache"}


def parse_elf(path):
    """(machine, needed, soname, rpaths) for a dynamic ELF, None for anything else."""
    try:
        with open(path, "rb") as f:
            hdr = f.read(64)
            if len(hdr) < 52 or hdr[:4] != b"\x7fELF" or hdr[5] != 1:
                return None
            is64 = hdr[4] == 2
            e_type, e_machine = struct.unpack_from("<HH", hdr, 16)
            if e_type not in (2, 3):  # ET_EXEC, ET_DYN
                return None
            if is64:
                e_phoff = struct.unpack_from("<Q", hdr, 32)[0]
                e_phentsize, e_phnum = struct.unpack_from("<HH", hdr, 54)
            else:
                e_phoff = struct.unpack_from("<I", hdr, 28)[0]
                e_phentsize, e_phnum = struct.unpack_from("<HH", hdr, 42)
            f.seek(e_phoff)
            ph = f.read(e_phentsize * e_phnum)
            loads, dyn = [], None
            for i in range(e_phnum):
                o = i * e_phentsize
                if is64:
                    p_type, _, p_offset, p_vaddr, _, p_filesz = struct.unpack_from("<IIQQQQ", ph, o)
                else:
                    p_type, p_offset, p_vaddr, _, p_filesz = struct.unpack_from("<IIIII", ph, o)
                if p_type == 1:
                    loads.append((p_vaddr, p_offset, p_filesz))
                elif p_type == 2:
                    dyn = (p_offset, p_filesz)
            if dyn is None:
                return (e_machine, [], None, [])  # static
            f.seek(dyn[0])
            d = f.read(dyn[1])
            size, fmt = (16, "<qQ") if is64 else (8, "<iI")
            needed, soname, rpaths, strtab, strsz = [], None, [], None, None
            for o in range(0, len(d) - size + 1, size):
                tag, val = struct.unpack_from(fmt, d, o)
                if tag == 0:
                    break
                if tag == 1:
                    needed.append(val)
                elif tag == 14:
                    soname = val
                elif tag in (15, 29):
                    rpaths.append(val)
                elif tag == 5:
                    strtab = val
                elif tag == 10:
                    strsz = val
            if strtab is None:
                return (e_machine, [], None, [])
            stroff = next((off + strtab - va for va, off, sz in loads if va <= strtab < va + sz), None)
            if stroff is None:
                return None
            f.seek(stroff)
            st = f.read(strsz or 1 << 20)
    except (OSError, struct.error):
        return None

    def s(o):
        return st[o:st.find(b"\0", o)].decode("utf-8", "replace")

    return (e_machine, [s(v) for v in needed], s(soname) if soname is not None else None,
            [p for v in rpaths for p in s(v).split(":") if p])


def resolve(root, path, hops=0):
    """The real in-rootfs path of an absolute rootfs path, following symlinks
    inside root (an absolute link target means root + target, not the host's)."""
    if hops > 40:
        return None
    parts = [p for p in path.split("/") if p]
    cur = ""
    for i, part in enumerate(parts):
        if part == "..":
            cur = cur.rsplit("/", 1)[0]
            continue
        if part == ".":
            continue
        nxt = cur + "/" + part
        host = root + nxt
        if os.path.islink(host):
            target = os.readlink(host)
            base = target if target.startswith("/") else cur + "/" + target
            rest = "/".join(parts[i + 1:])
            return resolve(root, base + ("/" + rest if rest else ""), hops + 1)
        if not os.path.lexists(host):
            return None
        cur = nxt
    return cur or "/"


def canon(p):
    return re.sub(r"^/(lib|lib64|bin|sbin)(/|$)", r"/usr/\1\2", p)


def main():
    root = os.path.abspath(sys.argv[1])
    armhf = "--armhf" in sys.argv[2:]
    machines = [EM_AARCH64] + ([EM_ARM] if armhf else [])

    owned = set()
    for lst in glob.glob(os.path.join(root, "var/lib/dpkg/info/*.list")):
        with open(lst, errors="replace") as f:
            owned.update(canon(line.rstrip("\n")) for line in f)

    extra_dirs = []
    for conf in glob.glob(os.path.join(root, "etc/ld.so.conf.d/*.conf")):
        with open(conf, errors="replace") as f:
            extra_dirs += [line.strip() for line in f if line.strip().startswith("/")]
    search = {}
    for m in machines:
        t = TRIPLET[m]
        search[m] = list(dict.fromkeys(
            [f"/usr/lib/{t}", f"/usr/local/lib/{t}", "/usr/local/lib", "/usr/lib", f"/lib/{t}", "/lib"] + extra_dirs))

    elf_cache = {}

    def elf_at(real):
        if real not in elf_cache:
            host = root + real
            elf_cache[real] = parse_elf(host) if os.path.isfile(host) else None
        return elf_cache[real]

    # name -> machines it is available for, by file name and by SONAME.
    avail = {}
    for m in machines:
        for d in search[m]:
            rd = resolve(root, d)
            if not rd or not os.path.isdir(root + rd):
                continue
            for name in os.listdir(root + rd):
                real = resolve(root, rd + "/" + name)
                e = elf_at(real) if real else None
                if not e:
                    continue
                avail.setdefault(name, set()).add(e[0])
                if e[2]:
                    avail.setdefault(e[2], set()).add(e[0])

    def found(lib, machine, rpaths, origin):
        if "/" in lib:
            return True  # a path, resolved against the cwd at run time
        if machine in avail.get(lib, ()):
            return True
        for rp in rpaths:
            d = rp.replace("${ORIGIN}", origin).replace("$ORIGIN", origin)
            real = resolve(root, d + "/" + lib)
            e = elf_at(real) if real else None
            if e and e[0] == machine:
                return True
        return False

    failures, warnings, checked = [], [], 0
    for dirpath, dirnames, filenames in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        rel = "" if rel == "." else rel
        dirnames[:] = [d for d in dirnames if (rel + "/" + d).lstrip("/") not in SKIP_DIRS]
        for fn in filenames:
            host = os.path.join(dirpath, fn)
            path = "/" + os.path.join(rel, fn) if rel else "/" + fn
            if os.path.islink(host) or canon(path) in owned:
                continue
            e = parse_elf(host)
            if not e or e[0] not in machines:
                continue
            checked += 1
            machine, needed, _, rpaths = e
            origin = os.path.dirname(path)
            missing = [n for n in needed if not found(n, machine, rpaths, origin)]
            if missing:
                line = f"  {path} ({ARCH_NAME[machine]}): {' '.join(missing)}"
                (warnings if WARN_ONLY.match(fn) else failures).append(line)

    for m in machines:
        missing = [n for n in SPRUCE_NEEDS[m] if m not in avail.get(n, ())]
        if missing:
            failures.append(f"  spruce needs these {ARCH_NAME[m]} libraries from the base: {' '.join(missing)}")

    print(f"Checked {checked} ELF files the build added on top of Debian, "
          f"and spruce's {sum(len(SPRUCE_NEEDS[m]) for m in machines)} base libraries.")
    if warnings:
        print("WARNING: prebuilt compat/Vulkan libraries with unresolved dependencies:")
        print("\n".join(warnings))
    if failures:
        print("ERROR: missing runtime libraries:")
        print("\n".join(failures))
        return 1
    print("All runtime libraries resolve.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
