# WebGPU backend - linux-4090

Rig: NVIDIA GeForce RTX 4090, Linux 6.8.0-149-generic x86_64, driver 595.91.07, Dawn v20260908.214631 / 94c3c9c. Case set v1.

| date | commit | tag | G | G_pp | G_tg | delta G |
|---|---|---|---|---|---|---|---|
| 2026-11-17 | 808d5f3d | base | 434.60 | 3450.02 | 92.15 | - |
| 2026-11-17 | 30dbdec5 | E001-quantize-reuse-r2-full | 448.97 | 3460.33 | 97.43 | +3.3% |
| 2026-11-17 | 08b8a5c5 | E014-mulmat-glu-full | 464.23 | 3448.90 | 103.16 | +3.4% |
| 2026-11-17 | b010ac77 | E010-mulmat-add-full | 485.63 | 3403.26 | 112.75 | +4.6% |

## latest

commit b010ac77, case_set v1, dawn v20260908.214631 / 94c3c9c, driver 595.91.07, dirty: no

| id | case | ts run1 | ts run2 | ts run3 | median | noise | ref_ts | ts/ref |
|---|---|---|---|---|---|---|---|---|
| a1 | smallest dense prefill | 10341.16 | 10898.87 | 10515.85 | 10515.85 | 5.3% | n/a | n/a |
| a2 | smallest dense decode | 147.00 | 145.13 | 144.95 | 145.13 | 1.4% | n/a | n/a |
| a3 | mid dense prefill | 4157.47 | 4162.10 | 4149.40 | 4157.47 | 0.3% | n/a | n/a |
| a4 | mid dense decode | 122.55 | 122.47 | 123.73 | 122.55 | 1.0% | n/a | n/a |
| a5 | MoE prefill | 905.22 | 900.99 | 903.35 | 903.35 | 0.5% | n/a | n/a |
| a6 | MoE decode | 75.36 | 83.50 | 83.92 | 83.50 | 10.3% | n/a | n/a |
| g1 | long-KV guard | 114.80 | 114.88 | 107.37 | 114.80 | 6.5% | n/a | n/a |

G = 485.63   G_pp = 3403.26   G_tg = 112.75
G range over invocations: [482.24, 491.90]
noise_agg = 2.0%

ops: 485 / 514 cases, W = 665.7 us
ppl = 9.8503 (corpus 173c87a5)
peak rss = 22828 MiB
load time = 10518 ms

## profile top shaders

- a1: mul_mat_subgroup_matrix_q8_0_f32 70.2 ms (74.3%), RMS_NORM_MUL 14.2 ms (15.0%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 5.7 ms (6.0%)
- a2: mul_mat_vec_q8_0_f32_sg_reduce 119.8 ms (17.1%), RMS_NORM_MUL 110.4 ms (15.8%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 90.7 ms (12.9%)
- a3: mul_mat_subgroup_matrix_q4_0_f32 221.2 ms (91.4%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 7.3 ms (3.0%), ADD_f32_inplace 4.4 ms (1.8%)
- a4: mul_mat_vec_q4_0_f32_add_residual_sg_reduce 264.0 ms (26.7%), mul_mat_vec_q4_0_f32_fuse_OP_SWIGLU_sg_reduce 175.1 ms (17.7%), quantize_q8_q4_0_sg_reduce 113.6 ms (11.5%)
- a5: mul_mat_id_mxfp4_f32 1126.9 ms (83.7%), mul_mat_subgroup_matrix_q8_0_f32 94.7 ms (7.0%), mul_mat_id_gather 59.6 ms (4.4%)
- a6: mul_mat_id_vec_mxfp4_f32_sg_reduce 988.5 ms (50.2%), mul_mat_vec_q8_0_f32_add_residual_sg_reduce 226.0 ms (11.5%), mul_mat_vec_q8_0_f32_sg_reduce 104.0 ms (5.3%)
- g1: mul_mat_subgroup_matrix_q4_0_f32 857.1 ms (36.7%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 436.0 ms (18.7%), mul_mat_vec_q4_0_f32_add_residual_sg_reduce 263.0 ms (11.3%)

