#!/usr/bin/env python3
# R36S clone: route audio to the headphones while they are plugged in.
#
# The rk817 codec only plays where its "Playback Path" control says, and on the
# rg351 kernel nothing changes that when the jack is used: the image restores
# SPK at boot, spruce's G350 profile expects the codec to switch by itself, and
# dArkOS's ogage, which did it there, is not built. The sound card does report
# the jack, as the SW_HEADPHONE_INSERT switch of its "... Headphones" input
# device, so this follows that switch: HP while it is on, SPK while it is off.
#
# /boot/headphones-invert reverses the switch, for a board whose detect pin
# reads the other way round (the G80CA-MB V1.2 20250422 and 20250423 differ).

import fcntl
import glob
import os
import re
import select
import struct
import subprocess
import sys
import time

CONTROL = "Playback Path"
INVERT_FLAG = "/boot/headphones-invert"
SW_HEADPHONE_INSERT = 0x02
EV_SW = 0x05
RECHECK_S = 5
# EVIOCGSW(len): _IOC(_IOC_READ, 'E', 0x1b, len)
EVIOCGSW = lambda n: (2 << 30) | (n << 16) | (ord("E") << 8) | 0x1B


def log(msg):
    print(f"hpjackd: {msg}", file=sys.stderr, flush=True)


def find_jack():
    for name_file in sorted(glob.glob("/sys/class/input/event*/device/name")):
        try:
            with open(name_file) as f:
                name = f.read().strip()
        except OSError:
            continue
        if name.endswith(" Headphones"):
            return "/dev/input/" + name_file.split("/")[4], name
    return None, None


def plugged(fd):
    buf = bytearray(8)
    fcntl.ioctl(fd, EVIOCGSW(len(buf)), buf)
    on = bool(buf[SW_HEADPHONE_INSERT // 8] & (1 << (SW_HEADPHONE_INSERT % 8)))
    return on != os.path.exists(INVERT_FLAG)


def current_path():
    out = subprocess.run(["amixer", "cget", f"name={CONTROL}"],
                         capture_output=True, text=True).stdout
    items = dict(re.findall(r"; Item #(\d+) '([^']*)'", out))
    m = re.search(r": values=(\d+)", out)
    return items.get(m.group(1)) if m else None


def set_path(path):
    subprocess.run(["amixer", "-q", "cset", f"name={CONTROL}", path])


def main():
    dev = name = None
    for _ in range(60):
        dev, name = find_jack()
        if dev:
            break
        time.sleep(1)
    if not dev:
        log("no headphone jack input device, nothing to do")
        return 0
    log(f"watching {dev} ({name})")
    fd = os.open(dev, os.O_RDONLY | os.O_NONBLOCK)
    last = None
    while True:
        want = "HP" if plugged(fd) else "SPK"
        have = current_path()
        if have is not None and have != want:
            set_path(want)
            if want != last:
                log(f"headphones {'in' if want == 'HP' else 'out'}: {CONTROL} {have} -> {want}")
        last = want
        if select.select([fd], [], [], RECHECK_S)[0]:
            try:
                while os.read(fd, 24 * 16):
                    pass
            except BlockingIOError:
                pass


if __name__ == "__main__":
    sys.exit(main())
