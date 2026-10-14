#!/usr/bin/env python3
"""Record the files available in KLC_DATA_DIR and log when they change.

Writes (in code/build/input/klc/ by default):
  klc_manifest.csv  current files: path, size_bytes, modified_utc, file_type, n_rows, columns,
                    sample_file, sample_recipe (the last four are kept if already filled in)
  klc_file_log.csv  append-only: detected_at_utc, event (new|modified|removed), path,
                    size_bytes, modified_utc

Usage: python3 code/scripts/klc/klc_manifest.py [--out-dir DIR]   (needs KLC access via klc-ssh.sh)
"""
import argparse, csv, datetime as dt, os, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
COLS = ["path", "size_bytes", "modified_utc", "file_type", "n_rows", "columns", "sample_file", "sample_recipe"]
LOG_COLS = ["detected_at_utc", "event", "path", "size_bytes", "modified_utc"]


def sh(*cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout


def remote_files():
    data_dir = sh("bash", "-c", f'source "{HERE}/klc-env.sh" && echo "$KLC_DATA_DIR"').strip()
    # skip git placeholders and the klc/ bookkeeping folder
    out = sh("bash", str(HERE / "klc-ssh.sh"), "run",
             f"cd '{data_dir}' && find . -type f ! -name .gitkeep ! -path './klc/*' -printf '%P\\t%s\\t%T@\\n'")
    files = {}
    for line in out.splitlines():
        p, size, mtime = line.split("\t")
        mod = dt.datetime.fromtimestamp(float(mtime), dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        files[p] = {"path": p, "size_bytes": size, "modified_utc": mod,
                    "file_type": os.path.splitext(p)[1].lstrip(".").lower()}
    return files


def read_csv(path):
    if not path.exists():
        return {}
    with open(path, newline="") as f:
        return {r["path"]: r for r in csv.DictReader(f)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", default=str(HERE.parents[1] / "build/input/klc"))
    out_dir = Path(ap.parse_args().out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest, log = out_dir / "klc_manifest.csv", out_dir / "klc_file_log.csv"

    old, new = read_csv(manifest), remote_files()
    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    events = []
    for p, r in sorted(new.items()):
        if p not in old:
            events.append((now, "new", p, r["size_bytes"], r["modified_utc"]))
        elif (old[p]["size_bytes"], old[p]["modified_utc"]) != (r["size_bytes"], r["modified_utc"]):
            events.append((now, "modified", p, r["size_bytes"], r["modified_utc"]))
    for p, r in sorted(old.items()):
        if p not in new:
            events.append((now, "removed", p, r["size_bytes"], r["modified_utc"]))

    with open(manifest, "w", newline="") as f:
        w = csv.DictWriter(f, COLS, lineterminator="\n")
        w.writeheader()
        for p in sorted(new):
            w.writerow({**{c: "" for c in COLS}, **{c: old.get(p, {}).get(c, "") for c in COLS[3:]}, **new[p]})
    new_log = not log.exists()
    with open(log, "a", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        if new_log:
            w.writerow(LOG_COLS)
        w.writerows(events)
    print(f"{len(new)} files on KLC; {len(events)} change(s) logged -> {out_dir}")


if __name__ == "__main__":
    sys.exit(main())
