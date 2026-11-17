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

## latest

commit e29dce01, case_set v1, dawn v20260908.214631 / 94c3c9c, driver 595.91.07, dirty: no

| id | case | ts run1 | ts run2 | ts run3 | median | noise | ref_ts | ts/ref |
|---|---|---|---|---|---|---|---|---|
| a1 | smallest dense prefill | 10345.48 | 10889.46 | 10998.95 | 10889.46 | 6.0% | n/a | n/a |
| a2 | smallest dense decode | 144.23 | 146.07 | 144.24 | 144.24 | 1.3% | n/a | n/a |
| a3 | mid dense prefill | 4149.27 | 4150.98 | 4150.73 | 4150.73 | 0.0% | n/a | n/a |
| a4 | mid dense decode | 123.40 | 121.60 | 123.54 | 123.40 | 1.6% | n/a | n/a |
| a5 | MoE prefill | 2762.67 | 2761.76 | 2767.00 | 2762.67 | 0.2% | n/a | n/a |
| a6 | MoE decode | 83.65 | 82.68 | 84.05 | 83.65 | 1.6% | n/a | n/a |
| g1 | long-KV guard | 116.05 | 117.53 | 116.17 | 116.17 | 1.3% | n/a | n/a |

G = 577.98   G_pp = 4997.83   G_tg = 114.65
G range over invocations: [573.84, 579.62]
noise_agg = 1.0%

ops: 485 / 514 cases, W = 611.9 us
ppl = 9.8503 (corpus 173c87a5)
peak rss = 22828 MiB
load time = 10131 ms

## profile top shaders

- a1: mul_mat_subgroup_matrix_q8_0_f32 68.3 ms (74.3%), RMS_NORM_MUL 13.8 ms (15.0%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 5.5 ms (6.0%)
- a2: mul_mat_vec_q8_0_f32_sg_reduce 119.4 ms (17.1%), RMS_NORM_MUL 110.2 ms (15.8%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 90.5 ms (13.0%)
- a3: mul_mat_subgroup_matrix_q4_0_f32 224.8 ms (91.4%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 7.4 ms (3.0%), ADD_f32_inplace 4.5 ms (1.8%)
- a4: mul_mat_vec_q4_0_f32_add_residual_sg_reduce 264.3 ms (26.7%), mul_mat_vec_q4_0_f32_fuse_OP_SWIGLU_sg_reduce 175.1 ms (17.7%), quantize_q8_q4_0_sg_reduce 113.8 ms (11.5%)
- a5: mul_mat_id_subgroup_matrix_mxfp4_f32 315.9 ms (55.0%), mul_mat_subgroup_matrix_q8_0_f32 113.6 ms (19.8%), mul_mat_id_gather 70.9 ms (12.3%)
- a6: mul_mat_id_vec_mxfp4_f32_sg_reduce 1027.7 ms (50.5%), mul_mat_vec_q8_0_f32_add_residual_sg_reduce 240.2 ms (11.8%), mul_mat_vec_q8_0_f32_sg_reduce 103.9 ms (5.1%)
- g1: mul_mat_subgroup_matrix_q4_0_f32 860.7 ms (40.3%), mul_mat_vec_q4_0_f32_add_residual_sg_reduce 263.4 ms (12.3%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 200.6 ms (9.4%)

