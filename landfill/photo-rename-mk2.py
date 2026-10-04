#!/usr/bin/env python3
"""
Rename a photo/video dump to <YYYYmmdd_HHMMSS.mmm>_<original name> so that lexical
order approximates Photos.app order (absolute instant; names rendered in --tz).

Timestamp selection (candidates = embedded metadata dates + mtime; "bogus" values
are discarded first -- see is_bogus()):

  default         first metadata date by priority (TAGS), else mtime
  --prefer-mtime  mtime, else first metadata date
  --oldest        the earliest of all remaining candidates

In every mode, metadata is only considered if the file looks device-authored
(Make matches --trusted-make, or it is an iOS screenshot); otherwise the file is
treated as mtime-only, with its metadata used strictly as a last resort.
--no-trust-check disables that gate.

Live Photo videos (matched to their still by ContentIdentifier, else by name) and
.AAE/.XMP sidecars inherit the timestamp chosen for their still.

Dry run unless --apply. Requires exiftool.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import shlex
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

STILL_EXT = {".heic", ".heif", ".jpg", ".jpeg", ".png", ".gif", ".tif", ".tiff", ".dng",
             ".webp", ".bmp", ".avif", ".jxl"}
VIDEO_EXT = {".mov", ".mp4", ".m4v", ".3gp", ".avi", ".mkv", ".webm"}
SIDECAR_EXT = {".aae", ".xmp"}
PREFIX = re.compile(r"^\d{8}_\d{6}\.\d{3}_")
DATE = re.compile(r"^(\d{4}):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)(\.\d+)?(Z|[+-]\d\d:?\d\d)?$")

# (exiftool tag as returned with -G1, how to interpret a missing zone, offset-fallback tags)
#   "utc"   -> naive value is UTC (QuickTime spec)
#   "local" -> naive value is wall time; try the listed OffsetTime* tags, else --naive-tz
TAGS = [
    ("Keys:CreationDate",                 "local", []),
    ("Composite:SubSecDateTimeOriginal",  "local", []),
    ("ExifIFD:DateTimeOriginal",          "local", ["ExifIFD:OffsetTimeOriginal", "ExifIFD:OffsetTime"]),
    ("XMP-exif:DateTimeOriginal",         "local", ["ExifIFD:OffsetTimeOriginal"]),
    ("UserData:DateTimeOriginal",         "local", []),
    ("Composite:SubSecCreateDate",        "local", []),
    ("ExifIFD:CreateDate",                "local", ["ExifIFD:OffsetTimeDigitized", "ExifIFD:OffsetTime"]),
    ("XMP-photoshop:DateCreated",         "local", []),
    ("XMP-xmp:CreateDate",                "local", []),
    ("Composite:DateTimeCreated",         "local", []),   # IPTC
    ("QuickTime:CreateDate",              "utc",   []),
    ("Track1:MediaCreateDate",            "utc",   []),
    ("Composite:SubSecModifyDate",        "local", []),
    ("IFD0:ModifyDate",                   "local", ["ExifIFD:OffsetTime"]),
]
EXTRA = ["Make", "UserComment", "ContentIdentifier", "ExifIFD:OffsetTimeOriginal",
         "ExifIFD:OffsetTimeDigitized", "ExifIFD:OffsetTime"]


def parse(s, naive, offsets, rec, naive_tz):
    """exiftool date string -> (epoch_ns, wall-clock tuple) or None."""
    if not isinstance(s, str):
        return None
    m = DATE.match(s.strip())
    if not m:
        return None  # includes 0000:00:00 and date-only values
    y, mo, d, h, mi, se, frac, tz = m.groups()
    if tz is None:
        for t in offsets:
            if isinstance(rec.get(t), str) and re.fullmatch(r"[+-]\d\d:\d\d", rec[t]):
                tz = rec[t]
                break
    try:
        dt = datetime.fromisoformat(f"{y}-{mo}-{d}T{h}:{mi}:{se}{frac or ''}"
                                    + ("" if tz is None else tz))
    except ValueError:
        return None
    if dt.tzinfo is None:
        if naive == "utc":
            dt = dt.replace(tzinfo=timezone.utc)
        elif naive_tz is not None:
            dt = dt.replace(tzinfo=naive_tz)
        else:
            dt = dt.astimezone()  # system local rules, DST-aware
    ns = int(dt.timestamp()) * 10**9 + dt.microsecond * 1000
    return ns, (int(y), int(mo), int(d), int(h), int(mi), int(se))


def is_bogus(ns, wall, min_ns, max_ns):
    if ns < min_ns or ns > max_ns:
        return True
    # common "zero" values: 1904/1970/1980/2000/2001-01-01 00:00:00 (QuickTime, Unix, DOS,
    # camera-reset, Core Data epochs)
    return wall is not None and wall[1:] == (1, 1, 0, 0, 0) and wall[0] <= 2001


def get(rec, suffix):
    for k, v in rec.items():
        if k.endswith(":" + suffix) and isinstance(v, (str, int)):
            return str(v)
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--prefer-mtime", action="store_true")
    mode.add_argument("--oldest", action="store_true")
    ap.add_argument("--no-trust-check", action="store_true", help="use metadata of all files")
    ap.add_argument("--trusted-make", default="Apple", help="regex for Make of device-authored files")
    ap.add_argument("--tz", default="UTC", help="zone the new names are rendered in")
    ap.add_argument("--naive-tz", help="zone for zone-less wall-clock metadata (default: system local)")
    ap.add_argument("--min-date", default="1990-01-01", help="dates before this are bogus")
    ap.add_argument("--explain", action="store_true", help="print all candidates per file")
    ap.add_argument("--apply", action="store_true", help="actually rename (default: dry run)")
    ap.add_argument("--fix-mtime", action="store_true", help="with --apply, also set mtime to the chosen date")
    a = ap.parse_args()

    out_tz = timezone.utc if a.tz == "UTC" else ZoneInfo(a.tz)
    naive_tz = ZoneInfo(a.naive_tz) if a.naive_tz else None
    min_ns = int(datetime.fromisoformat(a.min_date).replace(tzinfo=timezone.utc).timestamp()) * 10**9
    max_ns = (time.time_ns() + 86400 * 10**9)
    trusted_make = re.compile(a.trusted_make, re.I)

    media, sidecars = [], []
    for dirpath, dirnames, filenames in os.walk(a.root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]  # .stfolder, .stversions, ...
        for n in filenames:
            ext = os.path.splitext(n)[1].lower()
            p = os.path.join(dirpath, n)
            if n.startswith("."):
                continue
            (media if ext in STILL_EXT | VIDEO_EXT else sidecars if ext in SIDECAR_EXT else []).append(p)

    exiftool_cmd = (
        ["exiftool", "-j", "-G1", "-charset", "filename=utf8", "-api", "LargeFileSupport=1"]
        + ["-" + t for t, _, _ in TAGS]
        + ["-" + t for t in EXTRA]
        + ["-@", "-"]
    )
    proc = subprocess.run(
        ["parallel", "-j8", "--pipe", "--block=1k", "--round-robin", shlex.join(exiftool_cmd)],
        input="\n".join(media).encode(), capture_output=True)

    output = (proc.stdout or b"[]").decode('utf-8')
    docs = []
    while output:
        doc, pos = json.JSONDecoder().raw_decode(output)
        docs.append(doc)
        output = output[pos:].lstrip()

    meta = {r["SourceFile"]: r for doc in docs for r in doc}

    chosen = {}  # path -> (ns, source)
    info = {}    # path -> (is_video, content_id)
    for p in media:
        rec = meta.get(p, {})
        is_video = os.path.splitext(p)[1].lower() in VIDEO_EXT
        trusted = bool(trusted_make.fullmatch(get(rec, "Make") or "")) or get(rec, "UserComment") == "Screenshot"
        info[p] = (is_video, get(rec, "ContentIdentifier"))

        cands = []
        for tag, naive, offs in TAGS:
            r = parse(rec.get(tag), naive, offs, rec, naive_tz)
            if r:
                cands.append((tag, r[0], is_bogus(r[0], r[1], min_ns, max_ns)))
        mt = os.stat(p).st_mtime_ns
        mt_ok = not is_bogus(mt, None, min_ns, max_ns)

        good = [(t, ns) for t, ns, bogus in cands if not bogus]
        usable = good if (trusted or a.no_trust_check) else []
        mtime = [("mtime", mt)] if mt_ok else []
        if a.oldest:
            # same-second ties go to the earlier (usually more precise) entry in priority order
            pool = usable + mtime
            pick = min(pool, key=lambda c: (c[1] // 10**9, pool.index(c)), default=None)
        elif a.prefer_mtime:
            pick = (mtime + usable or [None])[0]
        else:
            pick = (usable + mtime or [None])[0]
        if pick is None and good:  # untrusted file whose mtime is bogus: last resort
            pick = good[0]
        if a.explain:
            print(f"# {p} trusted={trusted}", file=sys.stderr)
            for t, ns, bogus in cands + [("mtime", mt, not mt_ok)]:
                print(f"#   {t:34} {datetime.fromtimestamp(ns / 1e9, timezone.utc).isoformat()}"
                      f"{'  BOGUS' if bogus else ''}", file=sys.stderr)
        if pick is None:
            print(f"SKIP (no usable timestamp)\t{p}", file=sys.stderr)
            continue
        chosen[p] = (pick[1], pick[0] + ("" if trusted or pick[0] == "mtime" else "[untrusted]"))

    # Live Photo videos inherit their still's timestamp (Photos shows one asset dated by the still).
    stills = {p for p, (v, _) in info.items() if not v and p in chosen}
    by_cid = {info[p][1]: p for p in stills if info[p][1]}
    by_name = {}
    for p in stills:
        d, n = os.path.split(p)
        orig = PREFIX.sub("", n)
        by_name[os.path.join(d, orig)] = p                                 # IMG_1.HEIC.MOV
        #by_name.setdefault(os.path.join(d, os.path.splitext(orig)[0]), p)  # IMG_1.MOV
    def still_for(p):
        d, n = os.path.split(p)
        stem = os.path.splitext(PREFIX.sub("", n))[0]
        cands = [os.path.join(d, stem)]
        if os.path.basename(d) == "Live":
            cands.append(os.path.join(os.path.dirname(d), stem))
        return next((by_name[c] for c in cands if c in by_name), None)
    for p, (is_video, cid) in info.items():
        if is_video:
            s = by_cid.get(cid) if cid else None
            if s is None:  # name fallback, unless both sides carry conflicting identifiers
                s = still_for(p)
                if s and cid and info[s][1] not in (None, cid):
                    s = None
            if s:
                chosen[p] = (chosen[s][0], "paired:" + os.path.basename(PREFIX.sub("", s)))
    for p in sidecars:
        s = still_for(p)
        if s:
            chosen[p] = (chosen[s][0], "sidecar:" + os.path.basename(PREFIX.sub("", s)))

    planned, counts = set(), {}
    for p in sorted(chosen):
        ns, src = chosen[p]
        d, n = os.path.split(p)
        sec, rem = divmod(ns, 10**9)
        new = f"{datetime.fromtimestamp(sec, out_tz):%Y%m%d_%H%M%S}.{rem // 10**6:03d}_{PREFIX.sub('', n)}"
        key = src.split(":")[0] if src.startswith(("paired:", "sidecar:")) else src
        counts[key] = counts.get(key, 0) + 1
        dst = os.path.join(d, new)
        if new == n:
            continue
        if os.path.exists(dst) or dst in planned:
            print(f"SKIP (target exists)\t{p}", file=sys.stderr)
            continue
        planned.add(dst)
        print(f"{src}\t{p}\t-> {new}")
        if a.apply:
            os.rename(p, dst)
            if a.fix_mtime:
                os.utime(dst, ns=(ns, ns))

    for k, v in sorted(counts.items()):
        print(f"# {k}: {v}", file=sys.stderr)


if __name__ == "__main__":
    main()
