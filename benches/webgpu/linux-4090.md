# WebGPU backend - linux-4090

Rig: NVIDIA GeForce RTX 4090, Linux 6.8.0-149-generic x86_64, driver 595.91.07, Dawn v20260908.214631 / 94c3c9c. Case set v1.

| date | commit | tag | G | G_pp | G_tg | delta G |
|---|---|---|---|---|---|---|---|
| 2026-11-17 | 808d5f3d | base | 434.60 | 3450.02 | 92.15 | - |
| 2026-11-17 | 30dbdec5 | E001-quantize-reuse-r2-full | 448.97 | 3460.33 | 97.43 | +3.3% |
| 2026-11-17 | 08b8a5c5 | E014-mulmat-glu-full | 464.23 | 3448.90 | 103.16 | +3.4% |

## latest

commit 08b8a5c5, case_set v1, dawn v20260908.214631 / 94c3c9c, driver 595.91.07, dirty: no

| id | case | ts run1 | ts run2 | ts run3 | median | noise | ref_ts | ts/ref |
|---|---|---|---|---|---|---|---|---|
| a1 | smallest dense prefill | 10512.02 | 10949.05 | 11038.81 | 10949.05 | 4.8% | n/a | n/a |
| a2 | smallest dense decode | 134.48 | 136.51 | 136.08 | 136.08 | 1.5% | n/a | n/a |
| a3 | mid dense prefill | 4145.37 | 4138.91 | 4150.03 | 4145.37 | 0.3% | n/a | n/a |
| a4 | mid dense decode | 103.49 | 102.91 | 104.09 | 103.49 | 1.1% | n/a | n/a |
| a5 | MoE prefill | 905.11 | 905.27 | 905.42 | 905.27 | 0.0% | n/a | n/a |
| a6 | MoE decode | 81.50 | 81.39 | 81.82 | 81.50 | 0.5% | n/a | n/a |
| g1 | long-KV guard | 99.15 | 99.06 | 98.58 | 99.06 | 0.6% | n/a | n/a |

G = 464.23   G_pp = 3448.90   G_tg = 103.16
G range over invocations: [461.16, 465.54]
noise_agg = 0.9%

ops: 485 / 514 cases, W = 662.3 us
ppl = 9.8503 (corpus 173c87a5)
peak rss = 22828 MiB
load time = 10526 ms

## profile top shaders

- a1: mul_mat_subgroup_matrix_q8_0_f32 70.2 ms (74.3%), RMS_NORM_MUL 14.2 ms (15.0%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 5.7 ms (6.0%)
- a2: mul_mat_vec_q8_0_f32_sg_reduce 194.0 ms (25.9%), RMS_NORM_MUL 111.1 ms (14.9%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 90.5 ms (12.1%)
- a3: mul_mat_subgroup_matrix_q4_0_f32 218.8 ms (91.4%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 7.2 ms (3.0%), ADD_f32_inplace 4.4 ms (1.8%)
- a4: mul_mat_vec_q4_0_f32_sg_reduce 261.3 ms (23.1%), mul_mat_vec_q4_0_f32_fuse_OP_SWIGLU_sg_reduce 175.5 ms (15.5%), ADD_f32_inplace 144.8 ms (12.8%)
- a5: mul_mat_id_mxfp4_f32 1166.8 ms (83.2%), mul_mat_subgroup_matrix_q8_0_f32 102.9 ms (7.3%), mul_mat_id_gather 61.6 ms (4.4%)
- a6: mul_mat_id_vec_mxfp4_f32_sg_reduce 1036.7 ms (47.7%), mul_mat_vec_q8_0_f32_sg_reduce 382.4 ms (17.6%), ADD_f32_inplace 186.7 ms (8.6%)
- g1: mul_mat_subgroup_matrix_q4_0_f32 861.4 ms (34.8%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 435.6 ms (17.6%), mul_mat_vec_q4_0_f32_sg_reduce 260.5 ms (10.5%)

