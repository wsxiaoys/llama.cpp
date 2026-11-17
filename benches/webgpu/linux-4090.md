# WebGPU backend - linux-4090

Rig: NVIDIA GeForce RTX 4090, Linux 6.8.0-149-generic x86_64, driver 595.91.07, Dawn v20260908.214631 / 94c3c9c. Case set v1.

| date | commit | tag | G | G_pp | G_tg | delta G |
|---|---|---|---|---|---|---|---|
| 2026-11-17 | 808d5f3d | base | 434.60 | 3450.02 | 92.15 | - |
| 2026-11-17 | 30dbdec5 | E001-quantize-reuse-r2-full | 448.97 | 3460.33 | 97.43 | +3.3% |
| 2026-11-17 | 08b8a5c5 | E014-mulmat-glu-full | 464.23 | 3448.90 | 103.16 | +3.4% |
| 2026-11-17 | b010ac77 | E010-mulmat-add-full | 485.63 | 3403.26 | 112.75 | +4.6% |
| 2026-11-17 | 5e490d8e | E002-moe-subgroup-full | 574.25 | 4946.55 | 113.86 | +18.2% |

## latest

commit 5e490d8e, case_set v1, dawn v20260908.214631 / 94c3c9c, driver 595.91.07, dirty: no

| id | case | ts run1 | ts run2 | ts run3 | median | noise | ref_ts | ts/ref |
|---|---|---|---|---|---|---|---|---|
| a1 | smallest dense prefill | 10612.69 | 10824.04 | 10525.69 | 10612.69 | 2.8% | n/a | n/a |
| a2 | smallest dense decode | 145.55 | 145.76 | 145.88 | 145.76 | 0.2% | n/a | n/a |
| a3 | mid dense prefill | 4106.60 | 4114.05 | 4119.16 | 4114.05 | 0.3% | n/a | n/a |
| a4 | mid dense decode | 122.89 | 122.94 | 122.97 | 122.94 | 0.1% | n/a | n/a |
| a5 | MoE prefill | 2759.32 | 2762.59 | 2791.56 | 2762.59 | 1.2% | n/a | n/a |
| a6 | MoE decode | 83.27 | 82.16 | 82.12 | 82.16 | 1.4% | n/a | n/a |
| g1 | long-KV guard | 114.98 | 114.14 | 113.92 | 114.14 | 0.9% | n/a | n/a |

G = 574.25   G_pp = 4946.55   G_tg = 113.86
G range over invocations: [573.12, 574.58]
noise_agg = 0.3%

ops: 485 / 514 cases, W = 611.3 us
ppl = 9.8503 (corpus 173c87a5)
peak rss = 22827 MiB
load time = 10129 ms

## profile top shaders

- a1: mul_mat_subgroup_matrix_q8_0_f32 69.3 ms (74.3%), RMS_NORM_MUL 14.0 ms (15.0%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 5.6 ms (6.0%)
- a2: mul_mat_vec_q8_0_f32_sg_reduce 120.0 ms (17.1%), RMS_NORM_MUL 110.7 ms (15.8%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 90.9 ms (12.9%)
- a3: mul_mat_subgroup_matrix_q4_0_f32 222.7 ms (91.4%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 7.3 ms (3.0%), ADD_f32_inplace 4.4 ms (1.8%)
- a4: mul_mat_vec_q4_0_f32_add_residual_sg_reduce 264.4 ms (26.7%), mul_mat_vec_q4_0_f32_fuse_OP_SWIGLU_sg_reduce 175.2 ms (17.7%), quantize_q8_q4_0_sg_reduce 113.9 ms (11.5%)
- a5: mul_mat_id_subgroup_matrix_mxfp4_f32 362.6 ms (56.2%), mul_mat_subgroup_matrix_q8_0_f32 119.1 ms (18.5%), mul_mat_id_gather 80.7 ms (12.5%)
- a6: mul_mat_id_vec_mxfp4_f32_sg_reduce 1027.4 ms (50.3%), mul_mat_vec_q8_0_f32_add_residual_sg_reduce 244.7 ms (12.0%), mul_mat_vec_q8_0_f32_sg_reduce 104.0 ms (5.1%)
- g1: mul_mat_subgroup_matrix_q4_0_f32 864.0 ms (36.9%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 435.8 ms (18.6%), mul_mat_vec_q4_0_f32_add_residual_sg_reduce 263.2 ms (11.2%)

