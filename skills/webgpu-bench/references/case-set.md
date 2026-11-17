# Case set: models, commands, op derivation, shader map

## Model pins

Three models, frozen for the length of a chain. The repo id is not a pin: the first run records the
resolved file path and its sha256 in `meta.json`, and later runs must match it.

| alias | repo | quant | approx size | arch | why |
|---|---|---|---|---|---|
| `qwen3-0.6b-q8_0` | `Qwen/Qwen3-0.6B-GGUF` | Q8_0 | 0.6 GB | qwen3 (dense, GQA) | shortest case; host submit cost is visible; this repo ships only Q8_0 |
| `qwen2.5-3b-q4_0` | `Qwen/Qwen2.5-3B-Instruct-GGUF` | Q4_0 | 1.9 GB | qwen2 (dense, GQA) | mid-size prefill and decode; long-KV guard |
| `gpt-oss-20b-mxfp4` | `ggml-org/gpt-oss-20b-GGUF` | MXFP4 | 11.3 GB | gpt-oss (MoE) | `MUL_MAT_ID` and the expert gather path; the repo's own benchmark model |

Selection rules:

- Prefer Q4_0. If a repo has no Q4_0, use Q8_0 or MXFP4 and record it; all three are in the
  backend's `MUL_MAT` type list.
- Ungated repos only. A gated model makes the record unreproducible for anyone without access.
- One dense under 1B, one dense 3-4B, one MoE. A fourth model starts a new chain, because the case
  set and therefore the aggregate change.
- The model must fit the rig's memory at `-b 2048 -ub 512` and must load without falling
  back to CPU. Check with `GGML_SCHED_DEBUG=1`: one `## SPLIT` line means all nodes are on WebGPU.

If a model cannot be pinned or splits to CPU, replace it before the first record. Do not keep it
with a caveat: a case that runs partly on the CPU measures the CPU.

## Commands

Common flags: `-ngl 99 -fa on -ctk f16 -ctv f16 -b 2048 -ub 512 -r 5 -dev WebGPU`.

`-fa on` and f16 KV are pinned because the flash-attention path changes the op mix completely
(`FLASH_ATTN_EXT` plus `SOFT_MAX` vs `FLASH_ATTN_EXT` alone), and because `auto` resolves per model.

```sh
# a1, a2
./bin/llama-bench -hf Qwen/Qwen3-0.6B-GGUF:Q8_0 -p 512 -n 0 -r 5 -ngl 99 -fa on -dev WebGPU -o json
./bin/llama-bench -hf Qwen/Qwen3-0.6B-GGUF:Q8_0 -p 0 -n 128 -r 5 -ngl 99 -fa on -dev WebGPU -o json

# a3, a4, g1
./bin/llama-bench -hf Qwen/Qwen2.5-3B-Instruct-GGUF:Q4_0 -p 512 -n 0 -r 5 -ngl 99 -fa on -dev WebGPU -o json
./bin/llama-bench -hf Qwen/Qwen2.5-3B-Instruct-GGUF:Q4_0 -p 0 -n 128 -r 5 -ngl 99 -fa on -dev WebGPU -o json
./bin/llama-bench -hf Qwen/Qwen2.5-3B-Instruct-GGUF:Q4_0 -p 0 -n 128 -d 4096 -r 5 -ngl 99 -fa on -dev WebGPU -o json

# a5, a6
./bin/llama-bench -hf ggml-org/gpt-oss-20b-GGUF:MXFP4 -p 512 -n 0 -r 5 -ngl 99 -fa on -dev WebGPU -o json
./bin/llama-bench -hf ggml-org/gpt-oss-20b-GGUF:MXFP4 -p 0 -n 128 -r 5 -ngl 99 -fa on -dev WebGPU -o json
```

`-hf` downloads once into the HF cache. `run.sh` passes the resolved path from the JSON
`model_filename` field into `meta.json`, so later runs can use `-m <path>` and skip the lookup. A
curl-off build (`-DLLAMA_CURL=OFF`) cannot resolve `-hf`: pre-download the repos and map each id to
a local file in `$WEBGPU_BENCH_ROOT/models.tsv` (`repo<TAB>path`), which `run.sh` consults first
(override the path with `MODELS_MAP`).

## Deriving the op set

The graph tells you which ops the models run; the perf set tells you how fast they are. Run the
model once per test with scheduler debug on and collect the node lines:

```sh
GGML_SCHED_DEBUG=2 ./bin/llama-bench -m <model> -p 512 -n 0 -r 1 -ngl 99 -fa on -dev WebGPU -v \
    2> e2e/sched-a1.log
GGML_SCHED_DEBUG=2 ./bin/llama-bench -m <model> -p 0 -n 128 -r 1 -ngl 99 -fa on -dev WebGPU -v \
    2> e2e/sched-a2.log
```

`-v` is required: `GGML_SCHED_DEBUG` prints through the common logger, which drops DEBUG messages
unless the verbosity threshold is raised.

Each node line looks like:

```
node # 12 (       MUL_MAT):            blk.0.ffn_up.weight ( 1.50M) [WebGPU  WebGPU] use=1,c=1:...
```

The op name is the `(%10.10s)` field. The log holds one block per graph, so keep the last
`## SPLIT #0` block and count its node lines:

```sh
sed -n '/## SPLIT #0/,$p' e2e/sched-a2.log |
    sed -n 's/^node #[ 0-9]* ( *\([A-Z0-9_]*\)):.*/\1/p' | sort | uniq -c | sort -rn
```

The union over all seven logs is the `-o` filter for `test-backend-ops perf`. The counts go into
`ops/weights.json` as `{case id: {op: count}}`, one graph per log. A graph's op multiset is the same
for prefill and decode (only tensor sizes and the token count differ), so the weight is a per-graph
node count; there is a single `W`. `scripts/ops_filter.py` does this.

Two rules:

- Do not use the whole perf set. It contains CONV_2D/CONV_3D cases that take minutes and ops no
  model here executes.
- The op list is part of the record. If a commit changes it (new fusion, new op), that is a finding:
  compare the intersection of the two case lists and report the added and removed cases.

## Shader map

The GPU profile aggregates by pipeline name, not by ggml op. The names are the `variant` strings in
`ggml-webgpu-shader-lib.hpp`. This is the translation table for a profile frame:

| profile name | ggml op(s) | notes |
|---|---|---|
| `mul_mat_vec` | `MUL_MAT` | decode path, `ne[1] <= 4` |
| `mul_mat_reg_tile`, `mul_mat_subgroup_matrix` | `MUL_MAT` | prefill path; subgroup matrix is used when the adapter supports it |
| `mul_mat_id_gather` | `MUL_MAT_ID` | expert slot assignment, uses atomics |
| `mul_mat_id`, `mul_mat_id_vec` | `MUL_MAT_ID` | prefill and decode expert matmul |
| `flash_attn_vec`, `flash_attn_vec_blk`, `flash_attn_vec_reduce` | `FLASH_ATTN_EXT` | decode path |
| `flash_attn*` (tile and subgroup variants) | `FLASH_ATTN_EXT` | prefill path |
| `rms_norm`, `norm`, `l2_norm` | `RMS_NORM`, `NORM`, `L2_NORM` | |
| `RMS_NORM_MUL` | `RMS_NORM` + `MUL` | fused by `ggml_webgpu_encode`; two graph nodes, one shader |
| `rope` | `ROPE` | |
| `soft_max` | `SOFT_MAX` | |
| `get_rows` | `GET_ROWS` | |
| `cpy` | `CPY`, `DUP`, `CONT` | `CONT` is encoded as a copy |
| `glu` | `GLU` ops (`SWIGLU`, `GEGLU`, ...) | |
| `unary` | unary ops (`SILU`, `GELU`, `TANH`, ...) | name is the unary op name |
| `binary` | `ADD`, `SUB`, `MUL`, `DIV` | name is the ggml op name |
| `add_id`, `set_rows`, `set`, `concat`, `repeat`, `pad` | same-named ops | |
| `argmax`, `argsort`, `argsort_merge`, `cumsum`, `sum_rows`, `count_equal`, `scale` | same-named ops | |
| `quantize_q8` | `MUL_MAT` support | quantizes activations for the q8 path |
| `conv_2d`, `conv_2d_dw`, `im2col`, `upscale` | same-named ops | vision models only |
| `ssm_conv`, `ssm_scan`, `gated_delta_net`, `solve_tri` | same-named ops | hybrid/linear attention models |

Because of the fusions, a profile frame can be hotter than the op count suggests. Check
`ggml_webgpu_encode` before concluding that a frame is a separate kernel.

## Changing the case set

The case set is part of the measurement. Changing a model, a test length or a flag invalidates the
comparison with earlier records, so:

- a case-set change starts a new chain with a fresh `base` record,
- bump a `case_set` version string in `meta.json` (for example `v1`),
- never compare a `v2` record against a `v1` record, even on the same commit.
