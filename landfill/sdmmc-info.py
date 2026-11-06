#!/usr/bin/env python3
"""Decode SD card SCR and SD Status (SSR) from Linux sysfs.

Usage: sdinfo.py /sys/block/mmcblk0/device
"""
import sys
from pathlib import Path


def bits(n, hi, lo):
    return (n >> lo) & ((1 << (hi - lo + 1)) - 1)


def read_hex(dev, name):
    p = dev / name
    return int(p.read_text().strip(), 16) if p.exists() else None


def spec_version(scr):
    spec, spec3, spec4, specx = bits(scr, 59, 56), bits(scr, 47, 47), bits(scr, 42, 42), bits(scr, 41, 38)
    if spec == 0:
        return "1.0x"
    if spec == 1:
        return "1.10"
    if spec == 2 and not spec3:
        return "2.00"
    if specx:
        return {1: "5.xx", 2: "6.xx", 3: "7.xx", 4: "8.xx", 5: "9.xx"}.get(specx, f"specx={specx}")
    return "4.xx" if spec4 else "3.0x"


AU_SIZES = ["none", "16K", "32K", "64K", "128K", "256K", "512K", "1M",
            "2M", "4M", "8M", "12M", "16M", "24M", "32M", "64M"]


def main():
    dev = Path(sys.argv[1] if len(sys.argv) > 1 else "/sys/block/mmcblk0/device")
    for f in ("name", "manfid", "oemid", "hwrev", "fwrev", "date"):
        p = dev / f
        if p.exists():
            print(f"{f:10} {p.read_text().strip()}")

    scr = read_hex(dev, "scr")
    if scr is not None:
        cmd = bits(scr, 35, 32)
        print(f"\nSCR {scr:016x}")
        print(f"  spec version      {spec_version(scr)}")
        print(f"  CMD20 (speed cls) {bool(cmd & 1)}")
        print(f"  CMD23 (set count) {bool(cmd & 2)}")
        print(f"  CMD48/49 (ext reg) {bool(cmd & 4)}")
        print(f"  CMD58/59 (ext reg) {bool(cmd & 8)}")

    ssr = read_hex(dev, "ssr")
    if ssr is not None:
        sc = bits(ssr, 447, 440)
        pe = bits(ssr, 335, 328)
        print(f"\nSSR {ssr:0128x}")
        print(f"  speed class       {({0: 'C0', 1: 'C2', 2: 'C4', 3: 'C6', 4: 'C10'}).get(sc, sc)}")
        print(f"  UHS speed grade   U{bits(ssr, 399, 396)}")
        print(f"  video speed class V{bits(ssr, 391, 384)}")
        print(f"  app perf class    {({0: 'none', 1: 'A1', 2: 'A2'}).get(bits(ssr, 339, 336), '?')}")
        print(f"  AU size           {AU_SIZES[bits(ssr, 431, 428)]}")
        print(f"  UHS AU size       {AU_SIZES[bits(ssr, 395, 392)]}")
        print(f"  discard support   {bool(bits(ssr, 313, 313))}")
        print(f"  FULE support      {bool(bits(ssr, 312, 312))}")
        print(f"  PERFORMANCE_ENHANCE {pe:02x}:")
        print(f"    card-init maint {bool(pe & 0x80)}")
        print(f"    host-init maint {bool(pe & 0x40)}")
        print(f"    cache           {bool(pe & 0x20)}")
        print(f"    CQ depth field  {pe & 0x1f} (0 = no CQ)")

    # Raspberry Pi downstream kernels only: what the kernel decided to use
    for name, flags in (("ext_power", ["poweroff_notify", "power_sustenance", "power_down_mode"]),
                        ("ext_perf", ["fx_event", "card_maint", "host_maint", "cache", "cmd_queue"])):
        v = read_hex(dev, name)
        if v is not None:
            print(f"\nkernel {name}: " + ", ".join(f for i, f in enumerate(flags) if v & (1 << i)))


if __name__ == "__main__":
    main()
