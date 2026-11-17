#!/usr/bin/env python3
"""Regenerate benches/webgpu/<rig>.md from accepted records."""

import glob
import json
import os
import re
import sys

G_RE = re.compile(r"^G = ([0-9.]+)\s+G_pp = ([0-9.]+)\s+G_tg = ([0-9.]+)", re.M)
VALID = ("accepted", "needs-review")


def read_record(rec):
    with open(os.path.join(rec, "status.json")) as f:
        status = json.load(f).get("status")
    if status not in VALID:
        return None
    with open(os.path.join(rec, "meta.json")) as f:
        meta = json.load(f)
    with open(os.path.join(rec, "summary.md")) as f:
        summary = f.read()
    m = G_RE.search(summary)
    if not m:
        return None
    return {
        "meta": meta,
        "g": float(m.group(1)),
        "g_pp": float(m.group(2)),
        "g_tg": float(m.group(3)),
        "summary": summary,
    }


def main():
    root, out_path = sys.argv[1], sys.argv[2]
    records = []
    for rec in sorted(glob.glob(os.path.join(root, "runs", "*", "*"))):
        info = read_record(rec)
        if info:
            records.append(info)
    if not records:
        sys.exit("no accepted records under %s" % root)

    rig = records[-1]["meta"]["rig"]
    records = [r for r in records if r["meta"]["rig"] == rig]
    records.sort(key=lambda r: (r["meta"]["date"], r["meta"]["tag"]))

    meta = records[-1]["meta"]
    lines = [
        "# WebGPU backend - %s" % rig,
        "",
        "Rig: %s, %s, driver %s, Dawn %s. Case set %s." % (
            meta.get("gpu"), meta.get("os"), meta.get("driver", "?"), meta.get("dawn_version"), meta.get("case_set")),
        "",
        "| date | commit | tag | G | G_pp | G_tg | delta G |",
        "|---|---|---|---|---|---|---|---|",
    ]

    prev = None
    for r in records:
        if prev is None or prev[1] != r["meta"].get("case_set"):
            delta = "-"
        else:
            delta = "%+.1f%%" % (100 * (r["g"] / prev[0] - 1))
        lines.append("| %s | %s | %s | %.2f | %.2f | %.2f | %s |" % (
            r["meta"]["date"][:10], r["meta"]["commit"], r["meta"]["tag"],
            r["g"], r["g_pp"], r["g_tg"], delta))
        prev = (r["g"], r["meta"].get("case_set"))

    body = "\n".join(records[-1]["summary"].splitlines()[1:]).strip()
    lines += ["", "## latest", "", body, ""]

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("%s: %d records" % (out_path, len(records)))


if __name__ == "__main__":
    main()
