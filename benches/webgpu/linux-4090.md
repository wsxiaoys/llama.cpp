# WebGPU backend - linux-4090

Rig: NVIDIA GeForce RTX 4090, Linux 6.8.0-149-generic x86_64, driver 595.91.07, Dawn v20260908.214631 / 94c3c9c. Case set v1.

| date | commit | tag | G | G_pp | G_tg | delta G |
|---|---|---|---|---|---|---|---|
| 2026-11-17 | 808d5f3d | base | 434.60 | 3450.02 | 92.15 | - |
| 2026-11-17 | 30dbdec5 | E001-quantize-reuse-r2-full | 448.97 | 3460.33 | 97.43 | +3.3% |
| 2026-11-17 | 08b8a5c5 | E014-mulmat-glu-full | 464.23 | 3448.90 | 103.16 | +3.4% |
| 2026-11-17 | b010ac77 | E010-mulmat-add-full | 485.63 | 3403.26 | 112.75 | +4.6% |
| 2026-11-17 | 5e490d8e | E002-moe-subgroup-full | 574.25 | 4946.55 | 113.86 | +18.2% |
| 2026-11-17 | e29dce01 | E009-vec-nwg-full | 577.98 | 4997.83 | 114.65 | +0.6% |
| 2026-11-17 | a032ae69 | E008-moe-gather-skip-full | 586.12 | 5149.48 | 114.56 | +1.4% |
| 2026-11-17 | 0544c3bd | E024-mxfp4-lut-full | 603.65 | 5165.16 | 120.50 | +3.0% |

## base -> latest (per case)

| id | case | base ts | latest ts | delta |
|---|---|---|---|---|
| a1 | smallest dense prefill | 10923.20 | 10653.00 | -2.5% |
| a2 | smallest dense decode | 116.75 | 145.23 | +24.4% |
| a3 | mid dense prefill | 4149.12 | 4117.96 | -0.8% |
| a4 | mid dense decode | 88.88 | 122.37 | +37.7% |
| a5 | MoE prefill | 908.54 | 3122.40 | +243.7% |
| a6 | MoE decode | 80.60 | 99.55 | +23.5% |
| g1 | long-KV guard | 86.28 | 117.62 | +36.3% |
| **G** | geomean over cases | 434.60 | 603.65 | +38.9% |

## case set (models)

| id | model | quant | params | role | sha256 |
|---|---|---|---|---|---|
| a1 | Qwen/Qwen3-0.6B-GGUF | Q8_0 | p512 | smallest dense prefill | 9465e63a22ad |
| a2 | Qwen/Qwen3-0.6B-GGUF | Q8_0 | n128 | smallest dense decode | 9465e63a22ad |
| a3 | Qwen/Qwen2.5-3B-Instruct-GGUF | Q4_0 | p512 | mid dense prefill | 670d82d0fbee |
| a4 | Qwen/Qwen2.5-3B-Instruct-GGUF | Q4_0 | n128 | mid dense decode | 670d82d0fbee |
| a5 | ggml-org/gpt-oss-20b-GGUF | MXFP4 | p512 | MoE prefill | 27cd6c432c76 |
| a6 | ggml-org/gpt-oss-20b-GGUF | MXFP4 | n128 | MoE decode | 27cd6c432c76 |
| g1 | Qwen/Qwen2.5-3B-Instruct-GGUF | Q4_0 | n128 d4096 | long-KV guard | 670d82d0fbee |

## latest

commit 0544c3bd, case_set v1, dawn v20260908.214631 / 94c3c9c, driver 595.91.07, dirty: no

| id | case | ts run1 | ts run2 | ts run3 | median | noise | ref_ts | ts/ref |
|---|---|---|---|---|---|---|---|---|
| a1 | smallest dense prefill | 10653.00 | 11010.14 | 10642.12 | 10653.00 | 3.5% | n/a | n/a |
| a2 | smallest dense decode | 144.99 | 147.17 | 145.23 | 145.23 | 1.5% | n/a | n/a |
| a3 | mid dense prefill | 4142.78 | 4117.93 | 4117.96 | 4117.96 | 0.6% | n/a | n/a |
| a4 | mid dense decode | 122.22 | 122.37 | 123.90 | 122.37 | 1.4% | n/a | n/a |
| a5 | MoE prefill | 3122.40 | 3125.38 | 3120.95 | 3122.40 | 0.1% | n/a | n/a |
| a6 | MoE decode | 93.18 | 99.55 | 100.35 | 99.55 | 7.2% | n/a | n/a |
| g1 | long-KV guard | 116.88 | 117.62 | 118.27 | 117.62 | 1.2% | n/a | n/a |

G = 603.65   G_pp = 5165.16   G_tg = 120.50
G range over invocations: [595.63, 605.61]
noise_agg = 1.7%

ops: 485 / 514 cases, W = 597.6 us
ppl = 9.8503 (corpus 173c87a5)
peak rss = 22827 MiB
load time = 10195 ms

## profile top shaders

- a1: mul_mat_subgroup_matrix_q8_0_f32 68.5 ms (74.2%), RMS_NORM_MUL 13.8 ms (15.0%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 5.5 ms (6.0%)
- a2: mul_mat_vec_q8_0_f32_sg_reduce 119.6 ms (17.1%), RMS_NORM_MUL 110.2 ms (15.8%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 90.6 ms (13.0%)
- a3: mul_mat_subgroup_matrix_q4_0_f32 218.9 ms (91.4%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 7.2 ms (3.0%), ADD_f32_inplace 4.4 ms (1.8%)
- a4: mul_mat_vec_q4_0_f32_add_residual_sg_reduce 264.8 ms (26.7%), mul_mat_vec_q4_0_f32_fuse_OP_SWIGLU_sg_reduce 175.4 ms (17.7%), quantize_q8_q4_0_sg_reduce 114.1 ms (11.5%)
- a5: mul_mat_id_subgroup_matrix_mxfp4_f32 353.8 ms (64.0%), mul_mat_subgroup_matrix_q8_0_f32 119.8 ms (21.6%), flash_attn_kf16_vf16_qf32_dstf32_mask_sinks_k_direct_v_direct_hsqk64_hsv64 19.0 ms (3.4%)
- a6: mul_mat_id_vec_mxfp4_f32_sg_reduce 494.6 ms (31.9%), mul_mat_vec_q8_0_f32_add_residual_sg_reduce 257.1 ms (16.6%), mul_mat_vec_q8_0_f32_sg_reduce 125.1 ms (8.1%)
- g1: mul_mat_subgroup_matrix_q4_0_f32 860.3 ms (40.2%), mul_mat_vec_q4_0_f32_add_residual_sg_reduce 263.5 ms (12.3%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 200.7 ms (9.4%)

