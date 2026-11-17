#!/usr/bin/env python3
"""Build the test-backend-ops -o filter and the op weights from sched logs."""

import glob
import json
import os
import re
import sys

NODE_RE = re.compile(r"^node #\s*\d+ \(\s*([A-Z0-9_]+)\):", re.M)


def last_graph(text):
    # GGML_SCHED_DEBUG=2 prints one block per graph; the last one is a full graph
    idx = text.rfind("## SPLIT #0")
    return text[idx:] if idx >= 0 else text


def main():
    e2e_dir, weights_path = sys.argv[1], sys.argv[2]
    weights = {}

    for path in sorted(glob.glob(os.path.join(e2e_dir, "sched-*.log"))):
        cid = os.path.basename(path)[len("sched-"):-len(".log")]
        with open(path, errors="replace") as f:
            ops = NODE_RE.findall(last_graph(f.read()))
        counts = {}
        for op in ops:
            counts[op] = counts.get(op, 0) + 1
        weights[cid] = counts

    if not weights:
        sys.exit(1)

    os.makedirs(os.path.dirname(weights_path), exist_ok=True)
    with open(weights_path, "w") as f:
        json.dump(weights, f, indent=2, sort_keys=True)
        f.write("\n")

    union = sorted({op for counts in weights.values() for op in counts})
    print(",".join(union))


if __name__ == "__main__":
    main()
