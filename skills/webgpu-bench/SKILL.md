---
name: webgpu-bench
description: Measure and gate performance changes to the ggml WebGPU backend (Dawn) in llama.cpp - end-to-end pp/tg on pinned models plus per-op microbench derived from the model graphs, with the backend's own CPU and GPU profiles. Use when hill-climbing WebGPU performance, benchmarking a WebGPU change, or producing/refreshing a WebGPU baseline record.
---

# webgpu-bench: the measurement contract for the WebGPU backend

This is the benchmark skill that `hill-climb` requires. It supplies the measurement contract, the
record layout, the run commands and the gates. It also owns the back half of the loop: code + PR ->
pre-check -> build -> runs -> gate -> publish.

Scope: the native Dawn WebGPU backend (`ggml/src/ggml-webgpu`). The browser/wasm build, the
`wasi:webgpu` build and every other backend are out of scope - they are different rigs with
different noise and different bottlenecks. Do not mix their numbers into a WebGPU record.

## Contract (Phase 0 output)

```
BENCHMARK:   webgpu-bench - ggml WebGPU (Dawn) backend, native, on two pinned rigs
             (mac-arm64: Apple Silicon, linux-t4: NVIDIA T4); 3 GGUF models, 7 e2e cases
             (pp/tg) plus a per-op microbench derived from those models' graphs
RECORD:      $WEBGPU_BENCH_ROOT/runs/<rig>/<YYYYMMDD>-<commit8>-<tag>/ ; accepted = status.json
             {"status":"accepted"} (or needs-review) ; not-a-base = draft, blocked, abandoned
CASES:       summary.md (e2e: id, avg_ts per invocation, min/median/max, ref_ts) and
             ops/cases.md (op, params, us/run per invocation, min/median/max, noisy flag);
             aggregate = geomean avg_ts over the 7 e2e cases (G), reported with G_pp and G_tg;
             ops aggregate = W_pp, W_tg (node-weighted geomean us/run)
RUN:         scripts/run.sh <tag> ; 3 invocations x (7 cases x -r 5) ; profile subset = one
             invocation per case with the profile build ; wall time is recorded on the first
             baseline (budget 30-60 min per record) ; reuses the HF cache and the built binaries
PROFILES:    profile/<case>/{cpu,gpu,host}.txt ; cpu = "[ggml_webgpu cpu profiling summary]"
             "name: ms (pct)" ; gpu = "[ggml_webgpu gpu profiling summary]" "shader: ms (pct)" ;
             there is no inclusive flamegraph - host.txt (sample/perf) is the substitute
PRECHECK:    one test-backend-ops perf case (plus test mode) for a kernel change; one
             instrumented llama-bench run for a host-side change
DETERMINISM: test-backend-ops test on the touched ops, plus llama-perplexity PPL within 0.1% of
             the baseline on a pinned corpus ; known non-deterministic cases: none observed yet,
             confirm on the first two records
NOISE:       assumed +-5% per case and +-2% on G until two same-build records exist ; 3
             invocations give a range
PUBLISH:     $WEBGPU_BENCH_ROOT/runs/ (immutable) ; benches/webgpu/<rig>.md regenerated from
             accepted runs only ; <YYYYMMDD>-<commit8>-<tag>
PLAN:        $WEBGPU_BENCH_ROOT/experiments/E00N-<slug>/README.md ; frontmatter and status
             vocabulary from hill-climb references/experiment-plan.md ; queue =
             $WEBGPU_BENCH_ROOT/experiments/README.md
HANDOFF:     the verifier loads this skill (webgpu-bench) ; needs the plan file, the queue row,
             the baseline record path and the rig; returns the new record path plus the gate
             verdict, never a promoted baseline
```

`$WEBGPU_BENCH_ROOT` defaults to `~/webgpu-bench`. Records are large (SQL dumps, JSON, logs) and
must stay immutable, so they live outside the repo. Only the published summary goes into the repo.

## Why this shape

Three facts about this backend drive the design:

1. **The GPU profile is per shader, not per op.** `GGML_WEBGPU_GPU_PROFILE` wraps each compute pass
   in timestamp queries and aggregates by pipeline name (`mul_mat_vec`, `flash_attn_vec`, ...).
   `GGML_WEBGPU_CPU_PROFILE` aggregates by phase (`graph_compute`, `set_tensor`, `get_tensor`, ...).
   There is no inclusive flamegraph on either side. A profile therefore answers "which kernel or
   which phase", not "which line".
2. **The op graph is not the kernel list.** `ggml_webgpu_encode` fuses RMS_NORM+MUL and the GDN
   cache chain, so a shader can cover two graph nodes. The graph gives the case set; the profile
   gives the kernel names. Do not assume a 1:1 mapping.
3. **Per-op cases are cheap, the full perf set is not.** `test-backend-ops perf` runs each case for
   at least one second, and a few CONV_2D/CONV_3D cases take minutes each. Running the whole set
   costs more than the e2e run and measures ops no model in the set executes. Restrict it to the
   ops the benchmark models actually run.

## Rigs

| rig | machine | GPU API | Dawn | notes |
|---|---|---|---|---|
| `mac-arm64` | Apple Silicon, 32 GB+ | Metal via Dawn | pinned in `rigs/mac-arm64.json` | primary rig; one binary also has `MTL0`, so `ref_ts` is free |
| `linux-t4` | NVIDIA T4 16 GB, Ubuntu | Vulkan via Dawn | same pin | CI rig; `ref_ts` only if a CUDA build is available |

Rules:

- A record belongs to one rig. Never compare a mac record with a T4 record, and never put two rigs
  in one aggregate.
- Record the Dawn version, GPU driver version and OS build in `rigs/<rig>.json`. A Dawn bump is a
  new chain: re-baseline before trusting any delta.
- GPU timestamps are not available on every adapter. If the profile build aborts or reports 0 ms,
  mark `gpu.txt` as `unavailable` and fall back to `host.txt` plus the CPU breakdown.

## Build configs

```
bench          -DGGML_WEBGPU=ON -DCMAKE_BUILD_TYPE=Release
bench+profile  -DGGML_WEBGPU=ON -DCMAKE_BUILD_TYPE=Release \
               -DGGML_WEBGPU_CPU_PROFILE=ON -DGGML_WEBGPU_GPU_PROFILE=ON
```

Timed runs use `bench` only. The profile build adds per-batch query resolves and buffer maps, which
change the timing by a lot, especially for tg. Never compare across configs, and never publish a
number measured on `bench+profile`.

Build once per commit, in a separate directory per config. `meta.json` records the binary paths
that ran; the cmake line for each config lives in `rigs/<rig>.json`, because it is per rig and only
changes when the rig is rebuilt.

## Case set

### Tier A - e2e (the acceptance metric)

Seven cases, three models. `-ngl 99 -fa on -ctk f16 -ctv f16 -b 2048 -ub 512 -r 5`.

| id | model | test | role |
|---|---|---|---|
| `a1` | `qwen3-0.6b-q8_0` | `-p 512 -n 0` | smallest dense prefill |
| `a2` | `qwen3-0.6b-q8_0` | `-p 0 -n 128` | smallest dense decode; host overhead dominates |
| `a3` | `qwen2.5-3b-q4_0` | `-p 512 -n 0` | mid dense prefill; mul_mat compute |
| `a4` | `qwen2.5-3b-q4_0` | `-p 0 -n 128` | mid dense decode; mul_mat_vec + flash_attn |
| `a5` | `gpt-oss-20b-mxfp4` | `-p 512 -n 0` | MoE prefill; mul_mat_id |
| `a6` | `gpt-oss-20b-mxfp4` | `-p 0 -n 128` | MoE decode; mul_mat_id_vec |
| `g1` | `qwen2.5-3b-q4_0` | `-p 0 -n 128 -d 4096` | guard: long-KV attention |

Model selection rules, applied once and then frozen:

- One quant the backend lists for `MUL_MAT` (Q4_0 preferred; Q8_0 or MXFP4 where the repo has no
  Q4_0).
- One dense under 1B, one dense 3-4B, one MoE. Do not add a fourth model without a new chain.
- Must fit the smallest rig (16 GB) and load with `GGML_SCHED_DEBUG=1` showing one split. A model
  that splits to CPU is not a WebGPU case: replace it, do not keep it with a caveat.
- Record repo id, resolved file path, sha256, size and quant in `meta.json`. The repo id alone is
  not a pin.

`g1` is a guard, not a target: it exists so that an attention change that helps `a4` cannot quietly
destroy long-context decode.

### Tier B - per-op (the diagnostic metric)

Derive the op set from the models, do not take the whole perf list:

```sh
GGML_SCHED_DEBUG=2 ./bin/llama-bench -m <model> -p 512 -n 0 -r 1 -dev WebGPU 2> e2e/sched-a1.log
GGML_SCHED_DEBUG=2 ./bin/llama-bench -m <model> -p 0 -n 128 -r 1 -dev WebGPU 2> e2e/sched-a2.log
```

The log holds one graph per compute call, so take the last `## SPLIT #0` block and parse its
`node #NN (       OP):` lines into an op multiset. The union over the seven logs is the case filter:

```sh
./bin/test-backend-ops perf -b WebGPU --output sql -o '<op1,op2,...>' > ops/perf-1.sql
```

The node count per op is the weight. The weighted aggregate is

```
W = exp( sum_i w_i * ln(us_i) / sum_i w_i ),   w_i = nodes(op_i) / cases(op_i)
```

so an op that runs 200 times per token counts more than one that runs twice. `W_pp` uses the
prefill graphs (nodes per ubatch) and `W_tg` the decode graphs (nodes per token); they are not
comparable with each other. `W_pp` and `W_tg` are diagnostics: they tell you where the e2e time goes
and whether a kernel change moved it. They are not the keep gate.

Cases the backend does not support are printed as `not supported` and excluded. Record the count
(`n_supported / n_total`) in `summary.md`; a change in that count between baseline and candidate is
a finding, not noise.

### Tier C - reference gap (diagnostic only)

On `mac-arm64` the same binary exposes `MTL0`. Run the same seven cases with `-dev MTL0` and store
`ref_ts` next to `avg_ts`. Rank targets by `avg_ts / ref_ts`: the case furthest from the platform's
own backend is where the WebGPU implementation is weakest, which is more useful than ranking by
absolute t/s. On `linux-t4`, `ref_ts` needs a CUDA build; if it is absent the column is `n/a`.

`ref_ts` is never a gate. Metal and WebGPU have different kernels; the gap is a map, not a target.

## Record

```
$WEBGPU_BENCH_ROOT/
  rigs/<rig>.json
  runs/<rig>/<YYYYMMDD>-<commit8>-<tag>/
    meta.json            commit, dirty flag, Dawn, driver, OS, build configs, commands, model pins
    status.json          {"status": "draft|accepted|needs-review|blocked|abandoned", "note": ...}
    e2e/<id>-<invocation>.json
    e2e/<id>-ref.json    optional reference backend run (MTL0 / CUDA)
    e2e/sched-<id>.log   GGML_SCHED_DEBUG=2, one graph per log
    e2e/load.log         first-eval "load time = ..." lines
    e2e/rss.txt          /usr/bin/time -l (macOS) or -v (Linux) for each invocation
    e2e/ppl.txt          perplexity output for the determinism gate
    ops/perf-{1,2,3}.sql
    ops/cases.md         generated: op, params, us/run per invocation, min/median/max, noisy
    ops/weights.json     case id -> {op: node count}
    profile/<case>/{raw,cpu,gpu,host,meta}.txt
    summary.md           generated: case table, G, G_pp, G_tg, ranges, W_pp, W_tg
  experiments/
    README.md            the queue table
    E00N-<slug>/README.md
```

Status vocabulary: `draft` (incomplete, not a base), `accepted` (the only valid baseline),
`needs-review` (accepted with a caveat that cannot move a measured answer), `blocked`, `abandoned`.
A `needs-review` record is still a base; a `draft` is not.

Immutability: once `status.json` says `accepted`, nothing in the directory changes. A re-run is a
new directory with a new tag.

## Run

```sh
# one record = 3 invocations of the whole case set
skills/webgpu-bench/scripts/run.sh --tag base        # tag = base | E00N-<slug>

# or by hand, per invocations
./bin/llama-bench -m <model> -p 512 -n 0 -r 5 -ngl 99 -fa on \
    -dev WebGPU -o json > e2e/a1-1.json
```

`run.sh` writes `meta.json`, runs the invocations, derives the op set from the graph, runs the op
tier, and leaves `status.json` as `draft`. A human (or the hill-climb parent) promotes it to
`accepted` after the gates pass.

Profiles are separate, one case per invocation, and use the `bench+profile` binary. The flags are
compile-time, so there is no env var to set. Both summaries go to stdout, so capture stdout and
split it:

```sh
build-prof/bin/llama-bench -m <model> -p 0 -n 128 -r 1 -ngl 99 -fa on -dev WebGPU \
    > profile/a2/raw.txt 2>&1
awk '/cpu profiling summary/,/gpu profiling summary/' profile/a2/raw.txt > profile/a2/cpu.txt
awk '/gpu profiling summary/,0' profile/a2/raw.txt > profile/a2/gpu.txt
```

The backend prints both summaries when the backend is freed, so one invocation gives one case, not
a mixed aggregate. That is why the profile subset is "one invocation per case".

## Pre-check

Before spending a record, run the cheapest check that can falsify the hypothesis. One command,
under a minute.

| change | check | pass |
|---|---|---|
| kernel / shader | `test-backend-ops perf -b WebGPU -o '<OP>' -p '<case params>'`, then `test-backend-ops test -o '<OP>'` | the case time moves in the predicted direction and the test mode still passes |
| encode / submit / batch | one `llama-bench -p 0 -n 32 -r 1` on the profile build | `graph_compute` share or the named shader share moves; `set_tensor`/`get_tensor` do not grow |
| graph shape / fusion | `GGML_SCHED_DEBUG=2` node count plus the GPU profile shader count | fewer nodes or fewer kernels for the same output |
| buffer / memory | `/usr/bin/time -l` peak RSS on one case | RSS does not grow |

If the pre-check does not move, do not spend a record on it: write the number into the plan and
take the next experiment.

## Noise floor

Three invocations of the same build give a range. Report per case and on `G`:

- `NOISE_case` = `(max - min) / median` over the three invocation values.
- `NOISE_agg` = the same over the three `G` values.
- Until two same-build records exist, use `assumed: 5%` per case and `assumed: 2%` on `G`, and say
  so in the plan.

Expect tg on the 0.6B model to be the noisiest case: it is short, and host-side submit cost plus
CPU frequency scaling dominate. If `NOISE_case` for `a2` exceeds 10%, increase the case to
`-n 256` in the next chain rather than averaging harder.

Per-op cases below 50 us are timer-dominated. Mark them `noisy` and exclude them from `W`; keep
them in `cases.md` so a real regression there is still visible.

## Determinism

Two gates, both cheap:

1. `./bin/test-backend-ops test -b WebGPU -o '<touched ops>'` must pass. This is the existing
   CPU-vs-backend comparison, including the WebGPU f16 NMSE relaxation (1e-6). A kernel change that
   fails here is not a candidate.
2. `./bin/llama-perplexity -hf Qwen/Qwen2.5-3B-Instruct-GGUF:Q4_0 -f <corpus> -c 512 --chunks 8
   -ngl 99 -fa on -dev WebGPU` must land within 0.1% of the baseline PPL. Record the PPL in
   `summary.md`. The corpus is the CI wikitext-2 file; pin its sha256 in `meta.json`.

The backend uses atomics in `mul_mat_id_gather` (expert slot assignment) and `set_rows_quant`. The
slot order is not stable, but each output row is computed independently, so answers should be
stable. Confirm this on the first two records by comparing the two PPL values; if they differ by
more than 0.01%, record the case as non-deterministic and widen the gate instead of pretending the
difference is a regression.

## Gates

Stop and report instead of continuing when:

- run 1 of the candidate misses the target case by more than the plan predicted (give the number),
- a run fails, the model splits to CPU, or the profile build aborts,
- `test-backend-ops test` fails on a touched op,
- PPL moves more than 0.1%,
- a guard case regresses beyond its `NOISE_case`,
- peak RSS exceeds baseline + max(5%, 256 MiB).

Keep only when the candidate's `G` range does not overlap the baseline's `G` range and the delta
exceeds `NOISE_agg`. A case-level claim needs the same test on that case. Everything else is a
revert, including a point estimate that looks good but sits inside the spread.

## Publish

- Records: `$WEBGPU_BENCH_ROOT/runs/<rig>/...`, immutable.
- Summary: `benches/webgpu/<rig>.md`, regenerated by `scripts/publish.py` from `accepted` records
  only. One row per accepted run: date, commit, tag, `G`, `G_pp`, `G_tg`, delta vs the previous
  accepted row, and the per-case table for the latest row. Never hand-edit it.
- Naming: `<YYYYMMDD>-<commit8>-<tag>`, tag `base` for a baseline or `E00N-<slug>` for an
  experiment. The experiment id in the tag is how a record maps back to the question.

## Experiment handoff

The plan goes to `$WEBGPU_BENCH_ROOT/experiments/E00N-<slug>/README.md` using the hill-climb
`references/experiment-plan.md` template, and a row goes into `experiments/README.md`. This skill
then:

1. codes the change on a branch cut from `depends_on`,
2. runs the pre-check (one perf case + test mode, or one instrumented run),
3. builds `bench` and `bench+profile`,
4. runs `scripts/run.sh E00N-<slug>`,
5. applies the gates and fills `## Results` and `## Decision` from the record files only,
6. leaves `status.json` as `draft` with the verdict in the note.

Promotion to `accepted` and the publish step belong to the hill-climb parent, not to the run that
produced the candidate. A benchmark skill that promotes its own candidate has no gate.

## Anti-hack screen for this backend

Reject or rewrite a change that:

- only helps the exact shape of a `test-backend-ops perf` case and not the model shapes. The perf
  set is a proxy; a shape-specialized kernel is a benchmark hack unless the shape is a real model
  shape and the change still helps `a1`-`a6`.
- precomputes or caches results, or keys a cache on the input. Pipeline caching keyed on shape and
  type is fine and already exists.
- moves work out of the timed path without paying for it. Weight preprocessing at load is allowed,
  but load time and RSS are recorded and gated.
- tunes `command_submit_batch_size` or `max_inflight_batches` for one rig and regresses the other.
  The code has a TODO about per-platform tuning; a general default with a measured win on both rigs
  is fine, a constant flipped for one case is not.
- makes an unsupported op fall back to CPU and calls the missing GPU time a win.

## Failure modes

| symptom | cause | fix |
|---|---|---|
| GPU profile prints 0 ms or the profile build aborts | adapter has no timestamp-query support | mark `gpu.txt` unavailable, use the CPU breakdown and host sampling |
| numbers move after a Dawn update | Dawn is part of the measurement | pin Dawn per rig, re-baseline on change |
| tg swings 10%+ between invocations | short case, host submit cost, CPU frequency | raise `-n`, keep 3 invocations, never compare point estimates |
| one perf case runs for minutes | CONV_2D/CONV_3D shapes in the full perf set | restrict `-o` to the derived op set |
| `error: no device named '...'` | `-b` takes the device name, which is `WebGPU`, not the backend name | check `--list-devices`, do not guess |
| every case reports `not supported` | the op list includes ops this backend does not implement | expected; compare with `docs/ops/WebGPU.csv` |
| the op case list changed between records | the perf set is code | compare the intersection, report added/removed cases |
| a "win" disappears on the other rig | platform-specific path (subgroup matrix, dot product) | gate on the rig that owns the chain, report the other as informational |

## References

- `references/case-set.md` - model pins, exact commands, op derivation, shader-to-op map.
- `references/profiles.md` - the three profile sources, formats, caveats.
- `references/record.md` - record layout, generated files, publish recipe.
- `scripts/cases.tsv` - the case set: `id model p n d role`, one row per e2e case.
- `scripts/run.sh` - the harness that writes a record.
- `scripts/ops_filter.py` - derives the `-o` filter and the op weights from the sched logs.
- `scripts/summary.py` - builds `summary.md` and `ops/cases.md` from the raw files.
- `scripts/publish.py` - regenerates `benches/webgpu/<rig>.md` from accepted records.
