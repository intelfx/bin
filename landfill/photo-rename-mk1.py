#!/usr/bin/env python3
"""
Rename a Synctrain "photo back-up" dump so that lexical order == Photos.app order.

Date source per file (see Sushitrain/PhotoBackup.swift):
  * stills (incl. screenshots, saved images) and Live Photo MOVs:
      mtime -- Synctrain sets it to PHAsset.creationDate, which is exactly the
      date Photos sorts by (including "Adjust Date & Time" edits).
  * standalone videos (Synctrain >= v2.2.60 no longer sets their mtime, so it is
      the export time): Keys:CreationDate > QuickTime:CreateDate (UTC) > mtime.

New name: <YYYYmmdd_HHMMSS.mmm>_<original name>, rendered in --tz (default UTC,
so that names sort by absolute instant, as Photos does).

Dry run unless --apply. Requires exiftool (only for standalone videos).
"""
import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

VIDEO_EXT = {".mov", ".mp4", ".m4v", ".3gp", ".avi", ".mkv", ".webm"}
STILL_EXT = {".heic", ".heif", ".jpg", ".jpeg", ".png", ".gif", ".tif", ".tiff", ".dng", ".webp", ".bmp"}
DONE = re.compile(r"^\d{8}_\d{6}\.\d{3}_")
DATE = re.compile(r"^(\d{4}):(\d\d):(\d\d) (\d\d:\d\d:\d\d)(\.\d+)?(Z|[+-]\d\d:?\d\d)?$")


def parse_date(s, naive_is_utc):
    """Parse an exiftool date string to epoch ns; None if absent/invalid/ambiguous."""
    if not isinstance(s, str) or s.startswith("0000"):
        return None
    m = DATE.match(s.strip())
    if not m:
        return None
    y, mo, d, hms, frac, tz = m.groups()
    if tz is None:
        if not naive_is_utc:
            return None
        tz = "+00:00"
    dt = datetime.fromisoformat(f"{y}-{mo}-{d}T{hms}{frac or ''}{tz}")
    return int(dt.timestamp()) * 10**9 + dt.microsecond * 1000


def classify(dirpath, name, still_stems):
    stem, ext = os.path.splitext(name)
    if ext.lower() not in VIDEO_EXT:
        return "still"
    # Synctrain Live Photo naming: IMG_1234.HEIC.MOV (default), IMG_1234.MOV next to
    # IMG_1234.HEIC ("replace extension" option), or under Live/ (*AndType structures).
    if (os.path.splitext(stem)[1].lower() in STILL_EXT
            or os.path.basename(dirpath) == "Live"
            or stem in still_stems):
        return "live"
    return "video"


def video_dates(paths):
    if not paths:
        return {}
    out = subprocess.run(
        ["exiftool", "-j", "-G1", "-charset", "filename=utf8",
         "-Keys:CreationDate", "-QuickTime:CreateDate", "-@", "-"],
        input="\n".join(paths).encode(), capture_output=True, check=False)
    res = {}
    for rec in json.loads(out.stdout or b"[]"):
        ns = parse_date(rec.get("Keys:CreationDate"), naive_is_utc=False)
        src = "Keys:CreationDate"
        if ns is None:
            ns = parse_date(rec.get("QuickTime:CreateDate"), naive_is_utc=True)
            src = "QuickTime:CreateDate"
        if ns is not None:
            res[rec["SourceFile"]] = (ns, src)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("--apply", action="store_true", help="actually rename (default: dry run)")
    ap.add_argument("--tz", default="UTC", help="zone to render names in (default UTC)")
    ap.add_argument("--fix-mtime", action="store_true",
                    help="with --apply, also set standalone videos' mtime to the metadata date")
    args = ap.parse_args()
    tz = timezone.utc if args.tz == "UTC" else ZoneInfo(args.tz)

    files = []  # (dirpath, name, kind)
    for dirpath, dirnames, filenames in os.walk(args.root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]  # .stfolder, .stversions
        names = [n for n in filenames if not n.startswith(".") and not DONE.match(n)]
        still_stems = {os.path.splitext(DONE.sub("", n))[0] for n in filenames
                       if os.path.splitext(n)[1].lower() in STILL_EXT}
        files += [(dirpath, n, classify(dirpath, n, still_stems)) for n in names]

    vdates = video_dates([os.path.join(d, n) for d, n, k in files if k == "video"])

    planned, counts = set(), {}
    for dirpath, name, kind in sorted(files):
        path = os.path.join(dirpath, name)
        mtime_ns = os.stat(path).st_mtime_ns
        if kind == "video" and path in vdates:
            ns, src = vdates[path]
        else:
            ns, src = mtime_ns, "mtime" if kind != "video" else "mtime(UNRELIABLE)"
        counts[src] = counts.get(src, 0) + 1

        sec, rem = divmod(ns, 10**9)
        new = f"{datetime.fromtimestamp(sec, tz):%Y%m%d_%H%M%S}.{rem // 10**6:03d}_{name}"
        dst = os.path.join(dirpath, new)
        if os.path.exists(dst) or dst in planned:
            print(f"SKIP (target exists)\t{path}", file=sys.stderr)
            continue
        planned.add(dst)
        print(f"{src}\t{path}\t-> {new}")
        if args.apply:
            os.rename(path, dst)
            if args.fix_mtime and kind == "video" and path in vdates:
                os.utime(dst, ns=(ns, ns))

    print("\n".join(f"# {k}: {v}" for k, v in sorted(counts.items())), file=sys.stderr)


if __name__ == "__main__":
    main()
