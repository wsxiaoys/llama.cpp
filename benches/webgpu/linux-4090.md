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

## latest

commit a032ae69, case_set v1, dawn v20260908.214631 / 94c3c9c, driver 595.91.07, dirty: no

| id | case | ts run1 | ts run2 | ts run3 | median | noise | ref_ts | ts/ref |
|---|---|---|---|---|---|---|---|---|
| a1 | smallest dense prefill | 10653.76 | 10892.20 | 10519.84 | 10653.76 | 3.5% | n/a | n/a |
| a2 | smallest dense decode | 146.37 | 144.47 | 144.71 | 144.71 | 1.3% | n/a | n/a |
| a3 | mid dense prefill | 4123.74 | 4133.02 | 4139.52 | 4133.02 | 0.4% | n/a | n/a |
| a4 | mid dense decode | 121.75 | 121.80 | 123.48 | 121.80 | 1.4% | n/a | n/a |
| a5 | MoE prefill | 3108.11 | 3113.24 | 3108.12 | 3108.12 | 0.2% | n/a | n/a |
| a6 | MoE decode | 83.04 | 82.65 | 83.13 | 83.04 | 0.6% | n/a | n/a |
| g1 | long-KV guard | 117.77 | 116.60 | 115.93 | 116.60 | 1.6% | n/a | n/a |

G = 586.12   G_pp = 5149.48   G_tg = 114.56
G range over invocations: [584.51, 586.24]
noise_agg = 0.3%

ops: 485 / 514 cases, W = 639.4 us
ppl = 9.8503 (corpus 173c87a5)
peak rss = 22828 MiB
load time = 10208 ms

## profile top shaders

- a1: mul_mat_subgroup_matrix_q8_0_f32 66.8 ms (74.2%), RMS_NORM_MUL 13.5 ms (15.0%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 5.4 ms (6.0%)
- a2: mul_mat_vec_q8_0_f32_sg_reduce 119.5 ms (17.1%), RMS_NORM_MUL 110.1 ms (15.8%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 90.4 ms (12.9%)
- a3: mul_mat_subgroup_matrix_q4_0_f32 224.9 ms (91.4%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 7.4 ms (3.0%), ADD_f32_inplace 4.5 ms (1.8%)
- a4: mul_mat_vec_q4_0_f32_add_residual_sg_reduce 270.9 ms (27.0%), mul_mat_vec_q4_0_f32_fuse_OP_SWIGLU_sg_reduce 175.7 ms (17.5%), quantize_q8_q4_0_sg_reduce 115.4 ms (11.5%)
- a5: mul_mat_id_subgroup_matrix_mxfp4_f32 200.5 ms (62.9%), mul_mat_subgroup_matrix_q8_0_f32 72.2 ms (22.6%), flash_attn_kf16_vf16_qf32_dstf32_mask_sinks_k_direct_v_direct_hsqk64_hsv64 11.1 ms (3.5%)
- a6: mul_mat_id_vec_mxfp4_f32_sg_reduce 1002.7 ms (51.2%), mul_mat_vec_q8_0_f32_add_residual_sg_reduce 213.0 ms (10.9%), ADD_f32_inplace 100.6 ms (5.1%)
- g1: mul_mat_subgroup_matrix_q4_0_f32 859.8 ms (40.2%), mul_mat_vec_q4_0_f32_add_residual_sg_reduce 263.4 ms (12.3%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 200.5 ms (9.4%)

