# WebGPU backend - linux-4090

Rig: NVIDIA GeForce RTX 4090, Linux 6.8.0-149-generic x86_64, driver 595.91.07, Dawn v20260908.214631 / 94c3c9c. Case set v1.

| date | commit | tag | G | G_pp | G_tg | delta G |
|---|---|---|---|---|---|---|---|
| 2026-11-17 | 808d5f3d | base | 434.60 | 3450.02 | 92.15 | - |

## latest

commit 808d5f3d, case_set v1, dawn v20260908.214631 / 94c3c9c, driver 595.91.07, dirty: no

| id | case | ts run1 | ts run2 | ts run3 | median | noise | ref_ts | ts/ref |
|---|---|---|---|---|---|---|---|---|
| a1 | smallest dense prefill | 10655.11 | 10923.20 | 10934.80 | 10923.20 | 2.6% | n/a | n/a |
| a2 | smallest dense decode | 116.78 | 116.65 | 116.75 | 116.75 | 0.1% | n/a | n/a |
| a3 | mid dense prefill | 4149.12 | 4148.67 | 4149.47 | 4149.12 | 0.0% | n/a | n/a |
| a4 | mid dense decode | 88.88 | 90.14 | 88.60 | 88.88 | 1.7% | n/a | n/a |
| a5 | MoE prefill | 908.54 | 912.27 | 905.03 | 908.54 | 0.8% | n/a | n/a |
| a6 | MoE decode | 80.50 | 80.60 | 81.11 | 80.60 | 0.8% | n/a | n/a |
| g1 | long-KV guard | 86.28 | 86.38 | 84.99 | 86.28 | 1.6% | n/a | n/a |

G = 434.60   G_pp = 3450.02   G_tg = 92.15
G range over invocations: [433.91, 436.65]
noise_agg = 0.6%

ops: 485 / 514 cases, W = 663.2 us
ppl = 9.8503 (corpus 173c87a5)
peak rss = 22828 MiB
load time = 10487 ms

## profile top shaders

- a1: mul_mat_subgroup_matrix_q8_0_f32 68.7 ms (74.2%), RMS_NORM_MUL 13.8 ms (15.0%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 5.5 ms (6.0%)
- a2: mul_mat_vec_q8_0_f32_sg_reduce 269.3 ms (31.5%), quantize_q8_q8_0_sg_reduce 152.4 ms (17.8%), RMS_NORM_MUL 111.2 ms (13.0%)
- a3: mul_mat_subgroup_matrix_q4_0_f32 225.0 ms (91.4%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 7.4 ms (3.0%), ADD_f32_inplace 4.5 ms (1.8%)
- a4: mul_mat_vec_q4_0_f32_sg_reduce 464.5 ms (36.6%), quantize_q8_q4_0_sg_reduce 199.1 ms (15.7%), ADD_f32_inplace 145.1 ms (11.4%)
- a5: mul_mat_id_mxfp4_f32 1186.3 ms (83.7%), mul_mat_subgroup_matrix_q8_0_f32 101.4 ms (7.2%), mul_mat_id_gather 60.5 ms (4.3%)
- a6: mul_mat_id_vec_mxfp4_f32_sg_reduce 989.0 ms (47.3%), mul_mat_vec_q8_0_f32_sg_reduce 330.0 ms (15.8%), ADD_f32_inplace 182.5 ms (8.7%)
- g1: mul_mat_subgroup_matrix_q4_0_f32 861.4 ms (32.9%), mul_mat_vec_q4_0_f32_sg_reduce 465.1 ms (17.8%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 435.7 ms (16.6%)

