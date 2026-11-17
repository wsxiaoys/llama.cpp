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
| 2026-11-17 | 25a66eec | E027-split-k-prefill-full | 729.42 | 8061.19 | 121.20 | +20.8% |
| 2026-11-17 | e025ed08 | E026-mxfp4-sg-arith-full3 | 736.09 | 8253.29 | 120.55 | +0.9% |
| 2026-11-17 | 82c1c25f | E029-rmsnorm-reduce-full | 757.69 | 8778.96 | 120.42 | +2.9% |
| 2026-11-17 | 3fefab7a | E021-norm-quantize-full | 777.73 | 8837.80 | 125.66 | +2.6% |

## base -> latest (per case)

| id | case | base ts | latest ts | delta |
|---|---|---|---|---|
| a1 | smallest dense prefill | 10923.20 | 25928.95 | +137.4% |
| a2 | smallest dense decode | 116.75 | 156.51 | +34.1% |
| a3 | mid dense prefill | 4149.12 | 7178.74 | +73.0% |
| a4 | mid dense decode | 88.88 | 130.05 | +46.3% |
| a5 | MoE prefill | 908.54 | 3865.83 | +325.5% |
| a6 | MoE decode | 80.60 | 101.75 | +26.2% |
| g1 | long-KV guard | 86.28 | 119.88 | +38.9% |
| **G** | geomean over cases | 434.60 | 777.73 | +79.0% |

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

commit 3fefab7a, case_set v1, dawn v20260908.214631 / 94c3c9c, driver 595.91.07, dirty: no

| id | case | ts run1 | ts run2 | ts run3 | median | noise | ref_ts | ts/ref |
|---|---|---|---|---|---|---|---|---|
| a1 | smallest dense prefill | 24623.87 | 25928.95 | 25991.08 | 25928.95 | 5.3% | n/a | n/a |
| a2 | smallest dense decode | 157.17 | 155.35 | 156.51 | 156.51 | 1.2% | n/a | n/a |
| a3 | mid dense prefill | 7195.84 | 7178.74 | 7175.11 | 7178.74 | 0.3% | n/a | n/a |
| a4 | mid dense decode | 130.05 | 130.33 | 129.63 | 130.05 | 0.5% | n/a | n/a |
| a5 | MoE prefill | 3895.78 | 3530.07 | 3865.83 | 3865.83 | 9.5% | n/a | n/a |
| a6 | MoE decode | 101.75 | 102.05 | 99.68 | 101.75 | 2.3% | n/a | n/a |
| g1 | long-KV guard | 119.88 | 115.39 | 123.95 | 119.88 | 7.1% | n/a | n/a |

G = 777.73   G_pp = 8837.80   G_tg = 125.66
G range over invocations: [767.36, 783.17]
noise_agg = 2.0%

ops: 485 / 514 cases, W = 424.4 us
ppl = 9.8406 (corpus 173c87a5)
peak rss = 22828 MiB
load time = 10549 ms

## profile top shaders

- a1: mul_mat_subgroup_matrix_q8_0_f32_split4 24.4 ms (58.5%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 5.7 ms (13.7%), mul_mat_split_k_reduce 3.8 ms (9.1%)
- a2: mul_mat_vec_q8_0_f32_sg_reduce 119.9 ms (18.5%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 90.1 ms (13.9%), mul_mat_vec_q8_0_f32_add_residual_sg_reduce 74.3 ms (11.5%)
- a3: mul_mat_subgroup_matrix_q4_0_f32 57.7 ms (42.3%), mul_mat_subgroup_matrix_q4_0_f32_split4 54.4 ms (39.9%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 7.4 ms (5.4%)
- a4: mul_mat_vec_q4_0_f32_add_residual_sg_reduce 264.2 ms (28.6%), mul_mat_vec_q4_0_f32_fuse_OP_SWIGLU_sg_reduce 175.4 ms (18.9%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 111.0 ms (12.0%)
- a5: mul_mat_id_subgroup_matrix_mxfp4_f32 386.0 ms (72.7%), mul_mat_subgroup_matrix_q8_0_f32_split4 37.3 ms (7.0%), flash_attn_kf16_vf16_qf32_dstf32_mask_sinks_k_direct_v_direct_hsqk64_hsv64 23.2 ms (4.4%)
- a6: mul_mat_id_vec_mxfp4_f32_sg_reduce 483.6 ms (31.9%), mul_mat_vec_q8_0_f32_add_residual_sg_reduce 250.2 ms (16.5%), mul_mat_vec_q8_0_f32_sg_reduce 125.3 ms (8.3%)
- g1: mul_mat_vec_q4_0_f32_add_residual_sg_reduce 263.7 ms (15.9%), mul_mat_subgroup_matrix_q4_0_f32 221.2 ms (13.3%), mul_mat_subgroup_matrix_q4_0_f32_split4 208.5 ms (12.6%)

