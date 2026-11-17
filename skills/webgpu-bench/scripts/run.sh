#!/usr/bin/env bash
# Run one webgpu-bench record. See ../SKILL.md for the contract.
set -euo pipefail

usage() {
    cat <<'EOF'
usage: run.sh --tag <tag> [options]

  --tag <tag>        record tag: base | E00N-<slug>            (required)
  --rig <rig>        rig name, default linux-4090
  --fast             experiment record: e2e + ppl only (no ops, no profile, no sched)
  --no-ops           skip the per-op tier
  --no-profile       skip the profile tier
  --no-ppl           skip the perplexity check
  --fetch-corpus     download the wikitext-2 corpus if missing
  --dry-run          print the commands, write nothing

env: WEBGPU_BENCH_ROOT, BENCH_BIN, OPS_BIN, PPL_BIN, PROF_BIN, DEV, REPS, INVOCATIONS, MODELS_MAP
     OPS_INVOCATIONS (default 1), OPS_OPS (override the derived -o list), OPS_PARAMS (extra -p regex)
     timing lock: full records self-lock $WEBGPU_BENCH_ROOT/.gpu-timing.lock; --fast records may set
     WEBGPU_BENCH_GPU=<N> to self-lock .gpu-timing.lock.<N> and pin to GPU N (triage only);
     WEBGPU_BENCH_LOCK=0 disables, WEBGPU_LOCK_WAIT=<seconds> overrides the wait
EOF
}

TAG=""
RIG=""
FAST=0
DO_OPS=1
DO_PROFILE=1
DO_PPL=1
FETCH_CORPUS=0
DRY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)          TAG="$2"; shift 2 ;;
        --rig)          RIG="$2"; shift 2 ;;
        --fast)         FAST=1; DO_OPS=0; DO_PROFILE=0; shift ;;
        --no-ops)       DO_OPS=0; shift ;;
        --no-profile)   DO_PROFILE=0; shift ;;
        --no-ppl)       DO_PPL=0; shift ;;
        --fetch-corpus) FETCH_CORPUS=1; shift ;;
        --dry-run)      DRY=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              echo "unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

[[ -n "$TAG" ]] || { usage; exit 2; }

REPO_ROOT=$(git rev-parse --show-toplevel)
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${WEBGPU_BENCH_ROOT:-$HOME/webgpu-bench}
BENCH_BIN=${BENCH_BIN:-$REPO_ROOT/build/bin/llama-bench}
OPS_BIN=${OPS_BIN:-$REPO_ROOT/build/bin/test-backend-ops}
PPL_BIN=${PPL_BIN:-$REPO_ROOT/build/bin/llama-perplexity}
PROF_BIN=${PROF_BIN:-$REPO_ROOT/build-prof/bin/llama-bench}
DEV=${DEV:-WebGPU}
GPU=${WEBGPU_BENCH_GPU:-}
REPS=${REPS:-5}
INVOCATIONS=${INVOCATIONS:-3}
OPS_INVOCATIONS=${OPS_INVOCATIONS:-1}
OPS_OPS=${OPS_OPS:-}
OPS_PARAMS=${OPS_PARAMS:-}
CASES=${CASES:-$REPO_ROOT/skills/webgpu-bench/scripts/cases.tsv}
CORPUS=${PPL_CORPUS:-$ROOT/corpus/wiki.test.raw}
MODELS_MAP=${MODELS_MAP:-$ROOT/models.tsv}

RIG=${RIG:-linux-4090}

# Timed tiers finalize the same numbers, so gate/full records must not overlap: they use one global
# lock. --fast records and timing pre-checks may run on per-device locks + DRI_PRIME pinning
# (WEBGPU_BENCH_GPU=<N>) for triage; that is faster but higher-variance (P001), so gate decisions
# always come from global-lock runs. Non-timing work (builds, `test-backend-ops test`) needs no lock.
if [[ $DRY -eq 0 && -z "${WEBGPU_BENCH_LOCKED:-}" && "${WEBGPU_BENCH_LOCK:-1}" != 0 ]]; then
    LOCK_FILE=${WEBGPU_BENCH_LOCK_FILE:-$ROOT/.gpu-timing.lock}
    if [[ $FAST -eq 1 && -n "$GPU" ]]; then
        LOCK_FILE=$ROOT/.gpu-timing.lock.$GPU
        eval "$("$HERE/gpu-pin.sh" env "$GPU")"
    elif [[ -n "$GPU" ]]; then
        echo "run.sh: WEBGPU_BENCH_GPU=$GPU ignored for full records (global lock)" >&2
    fi
    if command -v flock >/dev/null; then
        export WEBGPU_BENCH_LOCKED=1
        mkdir -p "$(dirname "$LOCK_FILE")"
        exec flock -w "${WEBGPU_LOCK_WAIT:-7200}" "$LOCK_FILE" "$0" "$@"
    else
        echo "run.sh: flock not found; running without the timing lock" >&2
    fi
fi

COMMIT=$(git -C "$REPO_ROOT" rev-parse --short=8 HEAD)
DIRTY=0
git -C "$REPO_ROOT" diff --quiet && git -C "$REPO_ROOT" diff --cached --quiet || DIRTY=1
STAMP=$(date +%Y%m%d)
OUT="$ROOT/runs/$RIG/$STAMP-$COMMIT-$TAG"

COMMON=(-ngl 99 -fa on -ctk f16 -ctv f16 -b 2048 -ub 512 -dev "$DEV")

run() {
    if [[ $DRY -eq 1 ]]; then
        printf '+ %s\n' "$*"
    else
        "$@"
    fi
}

need() {
    [[ -x "$1" ]] || { echo "missing binary: $1" >&2; exit 1; }
}

need "$BENCH_BIN"
[[ $DO_OPS -eq 1 ]] && need "$OPS_BIN"
[[ $DO_PPL -eq 1 ]] && need "$PPL_BIN"
if [[ $DRY -eq 0 && ! -x /usr/bin/time ]]; then
    echo "missing /usr/bin/time (install GNU time: apt install time)" >&2
    exit 1
fi

if [[ $DRY -eq 0 ]]; then
    mkdir -p "$OUT"/{e2e,ops,profile}
fi

# one invocation per case keeps the profile tier and the per-case noise honest
# a curl-off build cannot resolve -hf; an optional models.tsv (repo<TAB>path) maps ids to files
model_args() {
    if [[ "$1" == /* || "$1" == .* ]]; then
        MARG=(-m "$1")
        return
    fi
    local path=""
    if [[ -f "$MODELS_MAP" ]]; then
        path=$(awk -F'\t' -v key="$1" '!/^#/ && $1==key {print $2; exit}' "$MODELS_MAP")
    fi
    if [[ -n "$path" ]]; then
        MARG=(-m "$path")
    else
        MARG=(-hf "$1")
    fi
}

rss_wrap() {
    local f=$1; shift
    /usr/bin/time -v -o "$f" -a "$@"
}

# fetch the corpus before meta.json so its sha256 is recorded on the first run
fetch_corpus() {
    [[ -s "$CORPUS" ]] && return 0
    [[ $FETCH_CORPUS -eq 1 ]] || return 0
    mkdir -p "$ROOT/corpus"
    curl -L --fail -o "$ROOT/corpus/wikitext-2-raw-v1.zip" \
        https://huggingface.co/datasets/ggml-org/ci/resolve/main/wikitext-2-raw-v1.zip
    # -j: the archive nests the .raw files under wikitext-2-raw/; flatten so $CORPUS exists
    unzip -o -j "$ROOT/corpus/wikitext-2-raw-v1.zip" -d "$ROOT/corpus"
}

write_meta() {
    local gpu driver os dawn
    gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || true)
    [[ -n "$gpu" ]] || gpu=$(lspci 2>/dev/null | sed -n 's/.*VGA compatible controller: //p' | head -1 || true)
    [[ -n "$gpu" ]] || gpu=unknown
    driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || true)
    [[ -n "$driver" ]] || driver=unknown
    os="$(uname -s) $(uname -r) $(uname -m)"
    dawn=${DAWN_VERSION:-unknown}
    if [[ -s "$ROOT/rigs/$RIG.json" ]]; then
        gpu=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("gpu", ""))' "$ROOT/rigs/$RIG.json")
        dawn=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("dawn_version", ""))' "$ROOT/rigs/$RIG.json")
        driver=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("driver", ""))' "$ROOT/rigs/$RIG.json")
    fi

    RIG_NAME=$RIG TAG_NAME=$TAG COMMIT=$COMMIT DIRTY=$DIRTY OS_NAME=$os GPU_NAME=$gpu \
    DRIVER=$driver DAWN=$dawn OUT_DIR=$OUT RIG_ROOT=$ROOT CASES_FILE=$CASES REPS=$REPS \
    INVOCATIONS=$INVOCATIONS OPS_INVOCATIONS=$OPS_INVOCATIONS DEV_NAME=$DEV \
    BENCH_BIN=$BENCH_BIN PROF_BIN=$PROF_BIN CORPUS=$CORPUS \
    python3 - <<'PY'
import json, os, subprocess, datetime

out = os.environ["OUT_DIR"]
meta = {
    "rig": os.environ["RIG_NAME"],
    "tag": os.environ["TAG_NAME"],
    "case_set": "v1",
    "commit": os.environ["COMMIT"],
    "dirty": os.environ["DIRTY"] == "1",
    "date": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "dawn_version": os.environ["DAWN"],
    "driver": os.environ["DRIVER"],
    "os": os.environ["OS_NAME"],
    "gpu": os.environ["GPU_NAME"],
    "device": os.environ["DEV_NAME"],
    "reps": int(os.environ["REPS"]),
    "invocations": int(os.environ["INVOCATIONS"]),
    "ops_invocations": int(os.environ["OPS_INVOCATIONS"]),
    "builds": {
        "bench": os.environ["BENCH_BIN"],
        "profile": os.environ["PROF_BIN"],
    },
    "models": {},
    "cases": [],
    "corpus": {"path": os.environ["CORPUS"], "sha256": None},
    "commands": [],
}

with open(os.environ["CASES_FILE"]) as f:
    for line in f:
        if line.startswith("#") or not line.strip():
            continue
        cid, model, p, n, d, role = line.rstrip("\n").split("\t")
        meta["models"].setdefault(model, {"repo": model, "path": None, "sha256": None, "bytes": None})
        meta["cases"].append({"id": cid, "model": model, "p": int(p), "n": int(n), "d": int(d), "role": role})

if os.path.exists(meta["corpus"]["path"]):
    for hasher in (["sha256sum"], ["shasum", "-a", "256"]):
        h = subprocess.run(hasher + [meta["corpus"]["path"]], capture_output=True, text=True)
        if h.returncode == 0:
            meta["corpus"]["sha256"] = h.stdout.split()[0]
            break

os.makedirs(out, exist_ok=True)
with open(os.path.join(out, "meta.json"), "w") as f:
    json.dump(meta, f, indent=2)
    f.write("\n")

# the first run on a rig creates its rig file; later runs must reuse it
rig_path = os.path.join(os.environ["RIG_ROOT"], "rigs", meta["rig"] + ".json")
if not os.path.exists(rig_path):
    os.makedirs(os.path.dirname(rig_path), exist_ok=True)
    with open(rig_path, "w") as f:
        json.dump({"rig": meta["rig"], "gpu": meta["gpu"], "os": meta["os"],
                   "dawn_version": meta["dawn_version"], "driver": meta["driver"],
                   "notes": ""}, f, indent=2)
        f.write("\n")
PY
}

if [[ $DRY -eq 0 ]]; then
    fetch_corpus
    write_meta
    printf '{"status": "draft", "note": "run.sh finished; gates not applied"}\n' > "$OUT/status.json"
fi

echo "record: $OUT"

# tier A: e2e, one invocation per case
while IFS=$'\t' read -r id model p n d _role; do
    [[ -z "$id" || "$id" == \#* ]] && continue
    model_args "$model"
    for i in $(seq 1 "$INVOCATIONS"); do
        echo "e2e $id run $i"
        if [[ $DRY -eq 1 ]]; then
            run "$BENCH_BIN" "${MARG[@]}" -p "$p" -n "$n" -d "$d" "${COMMON[@]}" -r "$REPS" -o json
        else
            rss_wrap "$OUT/e2e/rss.txt" "$BENCH_BIN" "${MARG[@]}" -p "$p" -n "$n" -d "$d" \
                "${COMMON[@]}" -r "$REPS" -o json > "$OUT/e2e/$id-$i.json" 2>> "$OUT/e2e/load.log"
        fi
    done
done < "$CASES"

# graph shape and op weights (only needed to derive the per-op tier)
if [[ $DO_OPS -eq 1 ]]; then
while IFS=$'\t' read -r id model p n d _role; do
    [[ -z "$id" || "$id" == \#* ]] && continue
    model_args "$model"
    echo "sched $id"
    if [[ $DRY -eq 1 ]]; then
        run env GGML_SCHED_DEBUG=2 "$BENCH_BIN" "${MARG[@]}" -p "$p" -n "$n" -d "$d" \
            -ngl 99 -fa on -dev "$DEV" -r 1 -v
    else
        GGML_SCHED_DEBUG=2 "$BENCH_BIN" "${MARG[@]}" -p "$p" -n "$n" -d "$d" \
            -ngl 99 -fa on -dev "$DEV" -r 1 -v > /dev/null 2> "$OUT/e2e/sched-$id.log" || true
    fi
done < "$CASES"
fi

# backfill the resolved model path and hash now that the first run resolved it
if [[ $DRY -eq 0 ]]; then
    OUT_DIR=$OUT python3 - <<'PY'
import hashlib, json, os

out = os.environ["OUT_DIR"]
path = os.path.join(out, "meta.json")
with open(path) as f:
    meta = json.load(f)

for case in meta["cases"]:
    info = meta["models"][case["model"]]
    if info["path"]:
        continue
    fn = os.path.join(out, "e2e", case["id"] + "-1.json")
    if not os.path.exists(fn):
        continue
    with open(fn) as f:
        row = json.load(f)[0]
    info["path"] = row["model_filename"]
    info["bytes"] = os.path.getsize(row["model_filename"])
    h = hashlib.sha256()
    with open(row["model_filename"], "rb") as f:
        for chunk in iter(lambda: f.read(1 << 24), b""):
            h.update(chunk)
    info["sha256"] = h.hexdigest()

with open(path, "w") as f:
    json.dump(meta, f, indent=2)
    f.write("\n")
PY
fi

# tier B: per-op, restricted to the ops the models run
if [[ $DO_OPS -eq 1 ]]; then
    if [[ -n "$OPS_OPS" ]]; then
        OPS="$OPS_OPS"
    else
        OPS=$(python3 "$REPO_ROOT/skills/webgpu-bench/scripts/ops_filter.py" "$OUT/e2e" "$OUT/ops/weights.json" || true)
    fi
    if [[ -n "$OPS" ]]; then
        OPPARGS=()
        [[ -n "$OPS_PARAMS" ]] && OPPARGS=(-p "$OPS_PARAMS")
        for i in $(seq 1 "$OPS_INVOCATIONS"); do
            echo "ops run $i: $OPS"
            if [[ $DRY -eq 1 ]]; then
                run "$OPS_BIN" perf -b "$DEV" --output sql -o "$OPS" "${OPPARGS[@]}"
            else
                "$OPS_BIN" perf -b "$DEV" --output sql -o "$OPS" "${OPPARGS[@]}" \
                    > "$OUT/ops/perf-$i.sql" 2> "$OUT/ops/perf-$i.log"
            fi
        done
    else
        echo "ops: no sched logs, skipped" >&2
    fi
fi

# tier C: profile, one case per invocation
if [[ $DO_PROFILE -eq 1 && -x "$PROF_BIN" ]]; then
    while IFS=$'\t' read -r id model p n d _role; do
        [[ -z "$id" || "$id" == \#* ]] && continue
        model_args "$model"
        echo "profile $id"
        if [[ $DRY -eq 1 ]]; then
            run "$PROF_BIN" "${MARG[@]}" -p "$p" -n "$n" -d "$d" "${COMMON[@]}" -r 1
        else
            mkdir -p "$OUT/profile/$id"
            "$PROF_BIN" "${MARG[@]}" -p "$p" -n "$n" -d "$d" "${COMMON[@]}" -r 1 \
                > "$OUT/profile/$id/raw.txt" 2>&1 || true
            awk '/cpu profiling summary/{f=1} /gpu profiling summary/{f=0} f' \
                "$OUT/profile/$id/raw.txt" > "$OUT/profile/$id/cpu.txt"
            awk '/gpu profiling summary/,0' "$OUT/profile/$id/raw.txt" > "$OUT/profile/$id/gpu.txt"
            printf '%s\n' "$PROF_BIN ${MARG[*]} -p $p -n $n -d $d ${COMMON[*]} -r 1" > "$OUT/profile/$id/meta.txt"
        fi
    done < "$CASES"
fi

# determinism: perplexity on the dense mid model
if [[ $DO_PPL -eq 1 ]]; then
    if [[ -s "$CORPUS" ]]; then
        model_args "Qwen/Qwen2.5-3B-Instruct-GGUF:Q4_0"
        echo "ppl"
        if [[ $DRY -eq 1 ]]; then
            run "$PPL_BIN" "${MARG[@]}" -f "$CORPUS" -c 512 --chunks 8 -ngl 99 -fa on -dev "$DEV"
        else
            "$PPL_BIN" "${MARG[@]}" -f "$CORPUS" -c 512 --chunks 8 -ngl 99 -fa on -dev "$DEV" \
                > "$OUT/e2e/ppl.txt" 2>&1 || true
        fi
    else
        echo "ppl: corpus missing ($CORPUS), skipped" >&2
    fi
fi

if [[ $DRY -eq 0 ]]; then
    python3 "$REPO_ROOT/skills/webgpu-bench/scripts/summary.py" "$OUT" "$CASES"
fi
