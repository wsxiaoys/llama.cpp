# Profiles: what the backend can tell you, and what it cannot

There are three sources. Only the first two are produced by the backend itself; the third is the
host sampler. There is no inclusive flamegraph for this backend, so a profile answers "which
shader" or "which phase", not "which line".

## 1. CPU breakdown (`GGML_WEBGPU_CPU_PROFILE=ON`)

Printed when the backend is freed, on stdout:

```
[ggml_webgpu cpu profiling summary]
ggml_webgpu: total cpu time: 1234.5 ms
ggml_webgpu: cpu breakdown:
ggml_webgpu:  graph_compute: 900.1 ms (72.9%)
ggml_webgpu:  set_tensor: 120.3 ms (9.7%)
ggml_webgpu:  get_tensor: 80.2 ms (6.5%)
...
```

Phases instrumented today: `graph_compute`, `memset_tensor`, `set_tensor`, `set_tensor_n`,
`get_tensor`, `get_tensor_n`, `clear`, `reg_get_device`. The "cpu detailed breakdown" section is
currently empty; do not expect it.

How to read it:

- `graph_compute` is encode + submit + wait for the graph. On decode it is dominated by per-node
  encode and per-batch submit, not by arithmetic.
- A large `set_tensor` or `get_tensor` share means the host is moving data per token. That is a
  target for a host-side change, not a shader change.
- `memset_tensor` shows up when the graph zeroes buffers per token. A growing share is usually a
  missing reuse, not a slow memset.

Caveat: the timers are wall-clock around the phase, so they include GPU wait when the phase blocks.
That is why `graph_compute` can exceed the sum of the shader times.

## 2. GPU breakdown (`GGML_WEBGPU_GPU_PROFILE=ON`)

Printed at the same time, on stdout:

```
[ggml_webgpu gpu profiling summary]
ggml_webgpu: total gpu time (all shaders): 812.3 ms

ggml_webgpu: gpu breakdown:
ggml_webgpu:  mul_mat_vec: 501.2 ms (61.70%)
ggml_webgpu:  flash_attn_vec: 180.4 ms (22.21%)
...
ggml_webgpu: gpu/cpu ratio: 0.66
```

Names are pipeline variants, not ggml ops. Use the shader map in `case-set.md` to translate.

How to read it:

- This is the only source that separates GPU work by kernel. It is the right input for "which kernel
  should I attack".
- The ratio line compares total shader time to total CPU time. Above 1 means the GPU is the
  bottleneck; well below 1 means the host is.
- Timestamps are per compute pass. A kernel that is split into several passes shows up as several
  entries with the same name; the backend already sums them.

Caveats:

- The flag requires adapter timestamp-query support. If the device fails to create or every value
  is 0, mark the profile `unavailable` and fall back to source 1 plus source 3.
- The flag sets `batch_compute_passes = false`, so every kernel gets its own compute pass instead
  of sharing one. The pass structure itself changes, not just the measurement overhead. A
  `bench+profile` build is never used for a record, and its numbers are not comparable with the
  `bench` build at all.
- The profiling code resolves a query set and maps a buffer at every batch boundary.
- The aggregate is per process. To profile one case, run one case per invocation (`-r 1`).

## 3. Host sampler (`host.txt`)

The substitute for an inclusive flamegraph, and the only way to see Dawn and the driver:

```sh
sample <pid> 10 -file profile/<case>/host.txt
```

Use it when the CPU breakdown says `graph_compute` is large but no shader is hot: the cost is then
inside Dawn (`wgpu::Queue::Submit`, `CreateCommandEncoder`, pipeline creation) or inside the
driver, and no backend-level change will remove it without changing the submit pattern.

## Which profile for which seam

| seam | source | first thing to look at |
|---|---|---|
| kernel math (mul_mat, flash_attn, glu, unary) | GPU | share of the named shader, then the matching perf case |
| encode / submit / batch size | CPU + host | `graph_compute` share, then Dawn frames in `host.txt` |
| buffer traffic per token (set/get tensor) | CPU | `set_tensor` + `get_tensor` share |
| graph shape / fusion | CPU + `GGML_SCHED_DEBUG=2` | node count per token vs shader count in the GPU profile |
| pipeline creation | host | `CreateComputePipeline` / cache misses in `host.txt` |

## Recording a profile

```
profile/<case>/cpu.txt   stdout of the profile build for that one case
profile/<case>/gpu.txt   the gpu summary lines (same stdout, split by run.sh)
profile/<case>/host.txt  sampler output, optional
profile/<case>/meta.txt  command line, build config, one case only, -r 1
```

`run.sh` writes `meta.txt` and splits the two summaries out of stdout. If a source is unavailable,
write a one-line file saying `unavailable: <reason>` rather than leaving it empty; a missing file
and an unavailable source mean different things to the next reader.
