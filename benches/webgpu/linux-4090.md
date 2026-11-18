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
| 2026-11-17 | 781e2278 | E022-moe-weighted-reduce-full | 793.30 | 8933.01 | 128.95 | +2.0% |
| 2026-11-17 | a694a4a1 | E031-split-k-shape-budget-full | 805.17 | 9275.22 | 128.77 | +1.5% |
| 2026-11-17 | d0fb6410 | E038-param-coalesce-full | 877.94 | 9344.57 | 148.99 | +9.0% |
| 2026-11-18 | b83d1e2a | E040-bindgroup-memo-full | 944.90 | 9262.45 | 170.56 | +7.6% |
| 2026-11-18 | 954911c2 | E020-qknorm-rope-full-clean | 957.58 | 9291.70 | 173.08 | +1.3% |
| 2026-11-18 | a670ca20 | E013-moe-addid-full | 958.07 | 9287.79 | 174.39 | +0.1% |

## base -> latest (per case)

| id | case | base ts | latest ts | delta |
|---|---|---|---|---|
| a1 | smallest dense prefill | 10923.20 | 27446.07 | +151.3% |
| a2 | smallest dense decode | 116.75 | 258.35 | +121.3% |
| a3 | mid dense prefill | 4149.12 | 7325.65 | +76.6% |
| a4 | mid dense decode | 88.88 | 186.61 | +110.0% |
| a5 | MoE prefill | 908.54 | 3985.35 | +338.7% |
| a6 | MoE decode | 80.60 | 128.76 | +59.8% |
| g1 | long-KV guard | 86.28 | 148.65 | +72.3% |
| **G** | geomean over cases | 434.60 | 958.07 | +120.4% |

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

commit a670ca20, case_set v1, dawn v20260908.214631 / 94c3c9c, driver 595.91.07, dirty: no

| id | case | ts run1 | ts run2 | ts run3 | median | noise | ref_ts | ts/ref |
|---|---|---|---|---|---|---|---|---|
| a1 | smallest dense prefill | 27498.52 | 27446.07 | 27373.06 | 27446.07 | 0.5% | n/a | n/a |
| a2 | smallest dense decode | 258.19 | 258.50 | 258.35 | 258.35 | 0.1% | n/a | n/a |
| a3 | mid dense prefill | 7348.34 | 7324.71 | 7325.65 | 7325.65 | 0.3% | n/a | n/a |
| a4 | mid dense decode | 186.61 | 186.61 | 186.57 | 186.61 | 0.0% | n/a | n/a |
| a5 | MoE prefill | 3981.53 | 3985.35 | 3995.47 | 3985.35 | 0.3% | n/a | n/a |
| a6 | MoE decode | 130.53 | 128.34 | 128.76 | 128.76 | 1.7% | n/a | n/a |
| g1 | long-KV guard | 148.30 | 149.37 | 148.65 | 148.65 | 0.7% | n/a | n/a |

G = 958.07   G_pp = 9287.79   G_tg = 174.39
G range over invocations: [957.74, 959.80]
noise_agg = 0.2%

ops: 485 / 514 cases, W = 398.0 us
ppl = 9.8355 (corpus 173c87a5)
peak rss = 22828 MiB
load time = 11261 ms

## profile top shaders

- a1: mul_mat_subgroup_matrix_q8_0_f32_split8 10.6 ms (28.8%), mul_mat_subgroup_matrix_q8_0_f32_split4 9.9 ms (26.6%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 5.6 ms (15.2%)
- a2: mul_mat_vec_q8_0_f32_sg_reduce 119.7 ms (19.9%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 89.8 ms (14.9%), mul_mat_vec_q8_0_f32_add_residual_sg_reduce 74.5 ms (12.4%)
- a3: mul_mat_subgroup_matrix_q4_0_f32 57.8 ms (43.7%), mul_mat_subgroup_matrix_q4_0_f32_split4 44.0 ms (33.3%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 7.4 ms (5.6%)
- a4: mul_mat_vec_q4_0_f32_add_residual_sg_reduce 264.7 ms (28.6%), mul_mat_vec_q4_0_f32_fuse_OP_SWIGLU_sg_reduce 175.6 ms (18.9%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 111.4 ms (12.0%)
- a5: mul_mat_id_subgroup_matrix_mxfp4_f32 279.8 ms (72.4%), flash_attn_kf16_vf16_qf32_dstf32_mask_sinks_k_direct_v_direct_hsqk64_hsv64 19.2 ms (5.0%), mul_mat_subgroup_matrix_q8_0_f32_split2 17.8 ms (4.6%)
- a6: mul_mat_id_vec_mxfp4_f32_sg_reduce 507.4 ms (35.6%), mul_mat_vec_q8_0_f32_add_residual_sg_reduce 257.7 ms (18.1%), mul_mat_vec_q8_0_f32_sg_reduce 125.3 ms (8.8%)
- g1: mul_mat_vec_q4_0_f32_add_residual_sg_reduce 264.4 ms (16.0%), mul_mat_subgroup_matrix_q4_0_f32 223.4 ms (13.6%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 200.8 ms (12.2%)

