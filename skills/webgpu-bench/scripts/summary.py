#!/usr/bin/env python3
"""Build summary.md and ops/cases.md from one record directory."""

import glob
import json
import math
import os
import re
import statistics
import sys

NOISY_US = 50.0
NOISY_PCT = 10.0


def load_cases(path):
    cases = []
    with open(path) as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            cid, model, p, n, d, role = line.rstrip("\n").split("\t")
            cases.append({"id": cid, "model": model, "p": int(p), "n": int(n), "d": int(d), "role": role})
    return cases


def geomean(values):
    values = [v for v in values if v > 0]
    if not values:
        return 0.0
    return math.exp(sum(math.log(v) for v in values) / len(values))


def spread(values):
    if len(values) < 2:
        return 0.0
    med = statistics.median(values)
    return (max(values) - min(values)) / med if med else 0.0


def load_e2e(out, cases):
    ts, ref = {}, {}
    for case in cases:
        runs = []
        for path in sorted(glob.glob(os.path.join(out, "e2e", case["id"] + "-*.json"))):
            if path.endswith("-ref.json"):
                continue
            with open(path) as f:
                rows = json.load(f)
            for row in rows:
                if (row["n_prompt"], row["n_gen"], row["n_depth"]) == (case["p"], case["n"], case["d"]):
                    runs.append(row["avg_ts"])
        ts[case["id"]] = runs
        ref_path = os.path.join(out, "e2e", case["id"] + "-ref.json")
        if os.path.exists(ref_path):
            with open(ref_path) as f:
                ref[case["id"]] = json.load(f)[0]["avg_ts"]
    return ts, ref


def load_ops(out):
    rows, total, supported = {}, 0, 0
    for path in sorted(glob.glob(os.path.join(out, "ops", "perf-*.sql"))):
        with open(path, errors="replace") as f:
            for line in f:
                if "INSERT INTO" not in line:
                    continue
                vals = re.findall(r"'([^']*)'", line)
                if len(vals) < 16:
                    continue
                total += 1
                if vals[6] != "1":
                    continue
                supported += 1
                key = (vals[3], vals[4])
                rows.setdefault(key, []).append(float(vals[9]))
    return rows, supported, total


def load_weights(out):
    path = os.path.join(out, "ops", "weights.json")
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return json.load(f)


def weighted(rows, weights, ids):
    # weight of one case = per-token node count of its op, split over the op's cases
    nodes = {}
    for cid in ids:
        for op, count in weights.get(cid, {}).items():
            nodes[op] = max(nodes.get(op, 0), count)
    per_case = {}
    for (op, _params) in rows:
        per_case[op] = per_case.get(op, 0) + 1
    terms, wsum = [], 0.0
    for (op, _params), runs in rows.items():
        if not runs or op not in nodes:
            continue
        us = statistics.median(runs)
        if us < NOISY_US or spread(runs) > NOISY_PCT:
            continue
        w = nodes[op] / per_case[op]
        terms.append(w * math.log(us))
        wsum += w
    return math.exp(sum(terms) / wsum) if wsum else 0.0


def load_ppl(out):
    path = os.path.join(out, "e2e", "ppl.txt")
    if not os.path.exists(path):
        return None
    with open(path, errors="replace") as f:
        m = re.search(r"Final estimate: PPL = ([0-9.]+)", f.read())
    return float(m.group(1)) if m else None


def load_rss(out):
    path = os.path.join(out, "e2e", "rss.txt")
    if not os.path.exists(path):
        return None
    best = 0
    with open(path, errors="replace") as f:
        for line in f:
            m = re.search(r"Maximum resident set size \(kbytes\):\s*(\d+)", line)
            if m:
                best = max(best, int(m.group(1)) // 1024)
                continue
            m = re.search(r"(\d+)\s+maximum resident set size", line)
            if m:
                best = max(best, int(m.group(1)) // (1024 * 1024))
    return best or None


def load_time(out):
    path = os.path.join(out, "e2e", "load.log")
    if not os.path.exists(path):
        return None
    best = 0.0
    with open(path, errors="replace") as f:
        for m in re.finditer(r"load time =\s*([0-9.]+) ms", f.read()):
            best = max(best, float(m.group(1)))
    return best or None


def profile_top(out, name, limit=3):
    path = os.path.join(out, "profile", name, "gpu.txt")
    if not os.path.exists(path):
        return []
    entries = []
    with open(path, errors="replace") as f:
        for line in f:
            m = re.search(r"ggml_webgpu:\s+(\w+):\s*([0-9.]+) ms \(([0-9.]+)%\)", line)
            if m:
                entries.append((m.group(1), float(m.group(2)), float(m.group(3))))
    entries.sort(key=lambda e: -e[1])
    return entries[:limit]


def main():
    out, cases_path = sys.argv[1], sys.argv[2]
    cases = load_cases(cases_path)
    ts, ref = load_e2e(out, cases)

    meta = {}
    if os.path.exists(os.path.join(out, "meta.json")):
        with open(os.path.join(out, "meta.json")) as f:
            meta = json.load(f)

    lines = []
    lines.append("# %s %s" % (meta.get("rig", "?"), os.path.basename(os.path.normpath(out))))
    lines.append("")
    lines.append("commit %s, case_set %s, dawn %s, dirty: %s" % (
        meta.get("commit", "?"), meta.get("case_set", "?"), meta.get("dawn_version", "?"),
        "yes" if meta.get("dirty") else "no"))
    lines.append("")
    n_inv = max((len(v) for v in ts.values()), default=1)
    lines.append("| id | case | " + " | ".join("ts run%d" % (i + 1) for i in range(n_inv)) +
                 " | median | noise | ref_ts | ts/ref |")
    lines.append("|---|---|" + "---|" * n_inv + "---|---|---|---|")

    for case in cases:
        runs = ts.get(case["id"], [])
        if not runs:
            lines.append("| %s | %s | missing |" % (case["id"], case["role"]) + " |" * 4)
            continue
        cells = ["%.2f" % v for v in runs]
        cells += [""] * (n_inv - len(cells))
        med = statistics.median(runs)
        r = ref.get(case["id"])
        ratio = "%.2f" % (med / r) if r else "n/a"
        lines.append("| %s | %s | %s | %.2f | %.1f%% | %s | %s |" % (
            case["id"], case["role"], " | ".join(cells), med, 100 * spread(runs),
            "%.2f" % r if r else "n/a", ratio))

    lines.append("")
    pp_ids = [c["id"] for c in cases if c["p"] > 0]
    tg_ids = [c["id"] for c in cases if c["p"] == 0]
    g_all = [geomean([ts[i][k] for i in ts if len(ts[i]) > k]) for k in range(max((len(v) for v in ts.values()), default=0))]
    g_pp = [geomean([ts[i][k] for i in pp_ids if len(ts[i]) > k]) for k in range(len(g_all))]
    g_tg = [geomean([ts[i][k] for i in tg_ids if len(ts[i]) > k]) for k in range(len(g_all))]
    lines.append("G = %.2f   G_pp = %.2f   G_tg = %.2f" % (
        statistics.median(g_all) if g_all else 0, statistics.median(g_pp) if g_pp else 0,
        statistics.median(g_tg) if g_tg else 0))
    if g_all:
        lines.append("G range over invocations: [%.2f, %.2f]" % (min(g_all), max(g_all)))
        lines.append("noise_agg = %.1f%%" % (100 * spread(g_all)))
    lines.append("")

    ops, n_supported, n_total = load_ops(out)
    weights = load_weights(out)
    if ops:
        lines.append("ops: %d / %d cases, W_pp = %.1f us, W_tg = %.1f us" % (
            n_supported, n_total, weighted(ops, weights, pp_ids), weighted(ops, weights, tg_ids)))
    else:
        lines.append("ops: none")

    ppl = load_ppl(out)
    if ppl is not None:
        lines.append("ppl = %.4f (corpus %s)" % (ppl, (meta.get("corpus", {}).get("sha256") or "?")[:8]))
    else:
        lines.append("ppl = n/a")

    rss = load_rss(out)
    lines.append("peak rss = %s" % ("%d MiB" % rss if rss else "n/a"))
    lt = load_time(out)
    lines.append("load time = %s" % ("%.0f ms" % lt if lt else "n/a"))
    lines.append("")

    profiled = sorted(os.path.basename(p) for p in glob.glob(os.path.join(out, "profile", "*")))
    if profiled:
        lines.append("## profile top shaders")
        lines.append("")
        for name in profiled:
            top = profile_top(out, name)
            if top:
                lines.append("- %s: %s" % (name, ", ".join("%s %.1f ms (%.1f%%)" % e for e in top)))
            else:
                lines.append("- %s: unavailable" % name)
        lines.append("")

    with open(os.path.join(out, "summary.md"), "w") as f:
        f.write("\n".join(lines) + "\n")

    if ops:
        write_ops(out, ops, weights, pp_ids, tg_ids)


def write_ops(out, ops, weights, pp_ids, tg_ids):
    def nodes_for(ids):
        nodes = {}
        for cid in ids:
            for op, count in weights.get(cid, {}).items():
                nodes[op] = max(nodes.get(op, 0), count)
        return nodes

    nodes_pp, nodes_tg = nodes_for(pp_ids), nodes_for(tg_ids)
    per_case = {}
    for (op, _params) in ops:
        per_case[op] = per_case.get(op, 0) + 1

    n_inv = max(len(v) for v in ops.values())
    lines = ["| op | params | " + " | ".join("us run%d" % (i + 1) for i in range(n_inv)) +
             " | median | noise | w_pp | w_tg | noisy |",
             "|---|---|" + "---|" * n_inv + "---|---|---|---|---|"]
    for (op, params), runs in sorted(ops.items(), key=lambda kv: -statistics.median(kv[1] or [0])):
        cells = ["%.1f" % v for v in runs]
        cells += [""] * (n_inv - len(cells))
        med = statistics.median(runs)
        s = spread(runs)
        noisy = med < NOISY_US or s > NOISY_PCT
        w_pp = nodes_pp.get(op, 0) / per_case[op]
        w_tg = nodes_tg.get(op, 0) / per_case[op]
        lines.append("| %s | %s | %s | %.1f | %.1f%% | %.3f | %.3f | %s |" % (
            op, params, " | ".join(cells), med, 100 * s, w_pp, w_tg, "yes" if noisy else "no"))
    with open(os.path.join(out, "ops", "cases.md"), "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
