# WebGPU backend - linux-4090

Rig: NVIDIA GeForce RTX 4090, Linux 6.8.0-149-generic x86_64, driver 595.91.07, Dawn v20260908.214631 / 94c3c9c. Case set v1.

| date | commit | tag | G | G_pp | G_tg | delta G |
|---|---|---|---|---|---|---|---|
| 2026-11-17 | 808d5f3d | base | 434.60 | 3450.02 | 92.15 | - |
| 2026-11-17 | 30dbdec5 | E001-quantize-reuse-r2-full | 448.97 | 3460.33 | 97.43 | +3.3% |

## latest

commit 30dbdec5, case_set v1, dawn v20260908.214631 / 94c3c9c, driver 595.91.07, dirty: no

| id | case | ts run1 | ts run2 | ts run3 | median | noise | ref_ts | ts/ref |
|---|---|---|---|---|---|---|---|---|
| a1 | smallest dense prefill | 10330.65 | 10945.59 | 11054.04 | 10945.59 | 6.6% | n/a | n/a |
| a2 | smallest dense decode | 126.58 | 124.91 | 125.07 | 125.07 | 1.3% | n/a | n/a |
| a3 | mid dense prefill | 4176.10 | 4176.95 | 4164.81 | 4176.10 | 0.3% | n/a | n/a |
| a4 | mid dense decode | 95.69 | 95.53 | 95.28 | 95.53 | 0.4% | n/a | n/a |
| a5 | MoE prefill | 906.47 | 906.26 | 905.58 | 906.26 | 0.1% | n/a | n/a |
| a6 | MoE decode | 81.34 | 81.20 | 82.17 | 81.34 | 1.2% | n/a | n/a |
| g1 | long-KV guard | 91.45 | 91.59 | 92.39 | 91.59 | 1.0% | n/a | n/a |

G = 448.97   G_pp = 3460.33   G_tg = 97.43
G range over invocations: [446.24, 450.59]
noise_agg = 1.0%

ops: 485 / 514 cases, W = 661.9 us
ppl = 9.8503 (corpus 173c87a5)
peak rss = 22828 MiB
load time = 10462 ms

## profile top shaders

- a1: mul_mat_subgroup_matrix_q8_0_f32 68.4 ms (74.2%), RMS_NORM_MUL 13.8 ms (15.0%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 5.5 ms (6.0%)
- a2: mul_mat_vec_q8_0_f32_sg_reduce 270.6 ms (34.2%), RMS_NORM_MUL 111.0 ms (14.0%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 90.4 ms (11.4%)
- a3: mul_mat_subgroup_matrix_q4_0_f32 223.9 ms (91.4%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 7.4 ms (3.0%), ADD_f32_inplace 4.5 ms (1.8%)
- a4: mul_mat_vec_q4_0_f32_sg_reduce 464.9 ms (39.2%), ADD_f32_inplace 145.1 ms (12.2%), quantize_q8_q4_0_sg_reduce 113.8 ms (9.6%)
- a5: mul_mat_id_mxfp4_f32 1095.9 ms (84.2%), mul_mat_subgroup_matrix_q8_0_f32 90.9 ms (7.0%), mul_mat_id_gather 55.8 ms (4.3%)
- a6: mul_mat_id_vec_mxfp4_f32_sg_reduce 1041.2 ms (48.6%), mul_mat_vec_q8_0_f32_sg_reduce 349.7 ms (16.3%), ADD_f32_inplace 186.6 ms (8.7%)
- g1: mul_mat_subgroup_matrix_q4_0_f32 861.5 ms (34.0%), mul_mat_vec_q4_0_f32_sg_reduce 465.1 ms (18.4%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 435.2 ms (17.2%)

