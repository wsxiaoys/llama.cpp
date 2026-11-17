#!/usr/bin/env python3
"""Regenerate benches/webgpu/<rig>.md from accepted records."""

import glob
import json
import os
import re
import sys

G_RE = re.compile(r"^G = ([0-9.]+)\s+G_pp = ([0-9.]+)\s+G_tg = ([0-9.]+)", re.M)
CASE_IDS = ("a1", "a2", "a3", "a4", "a5", "a6", "g1")
VALID = ("accepted", "needs-review")


def case_medians(summary):
    """{case id: (name, median ts)} from a record summary's case table."""
    out = {}
    for line in summary.splitlines():
        if not line.startswith("| "):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) >= 8 and parts[1] in CASE_IDS:
            try:
                out[parts[1]] = (parts[2], float(parts[6]))
            except ValueError:
                pass
    return out


def case_set_table(meta):
    """Markdown rows mapping every case to the model/quant it runs, from meta.json."""
    cases = meta.get("cases", [])
    if not cases:
        return []
    models = meta.get("models", {})
    out = ["## case set (models)", "",
           "| id | model | quant | params | role | sha256 |", "|---|---|---|---|---|---|"]
    for c in cases:
        ref = c.get("model", "?")
        repo, _, quant = ref.rpartition(":")
        if not repo:
            repo, quant = ref, ""
        params = " ".join("%s%d" % (k, c[k]) for k in ("p", "n", "d") if c.get(k))
        sha = models.get(ref, {}).get("sha256", "")[:12]
        out.append("| %s | %s | %s | %s | %s | %s |" % (
            c.get("id", "?"), repo, quant, params, c.get("role", ""), sha))
    return out


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

    first, last = records[0], records[-1]
    base_cases = case_medians(first["summary"])
    last_cases = case_medians(last["summary"])
    if base_cases and last_cases and first["meta"].get("case_set") == last["meta"].get("case_set"):
        lines += ["", "## base -> latest (per case)", "",
                  "| id | case | base ts | latest ts | delta |", "|---|---|---|---|---|"]
        for cid in CASE_IDS:
            if cid in base_cases and cid in last_cases:
                name, b = base_cases[cid]
                _, l = last_cases[cid]
                lines.append("| %s | %s | %.2f | %.2f | %+.1f%% |" % (cid, name, b, l, 100 * (l / b - 1)))
        lines.append("| **G** | geomean over cases | %.2f | %.2f | %+.1f%% |" % (
            first["g"], last["g"], 100 * (last["g"] / first["g"] - 1)))

    cst = case_set_table(last["meta"])
    if cst:
        lines += [""] + cst

    body = "\n".join(records[-1]["summary"].splitlines()[1:]).strip()
    lines += ["", "## latest", "", body, ""]

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("%s: %d records" % (out_path, len(records)))


if __name__ == "__main__":
    main()
