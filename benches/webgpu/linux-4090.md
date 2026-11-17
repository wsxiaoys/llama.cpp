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

## latest

commit 25a66eec, case_set v1, dawn v20260908.214631 / 94c3c9c, driver 595.91.07, dirty: no

| id | case | ts run1 | ts run2 | ts run3 | median | noise | ref_ts | ts/ref |
|---|---|---|---|---|---|---|---|---|
| a1 | smallest dense prefill | 19258.13 | 20361.36 | 20380.46 | 20361.36 | 5.5% | n/a | n/a |
| a2 | smallest dense decode | 147.79 | 146.65 | 146.51 | 146.65 | 0.9% | n/a | n/a |
| a3 | mid dense prefill | 7178.95 | 7160.50 | 7129.74 | 7160.50 | 0.7% | n/a | n/a |
| a4 | mid dense decode | 123.60 | 124.48 | 123.53 | 123.60 | 0.8% | n/a | n/a |
| a5 | MoE prefill | 3606.83 | 3592.92 | 3606.52 | 3606.52 | 0.4% | n/a | n/a |
| a6 | MoE decode | 101.79 | 100.33 | 100.26 | 100.33 | 1.5% | n/a | n/a |
| g1 | long-KV guard | 118.49 | 117.81 | 111.30 | 117.81 | 6.1% | n/a | n/a |

G = 729.42   G_pp = 8061.19   G_tg = 121.20
G range over invocations: [725.54, 732.38]
noise_agg = 0.9%

ops: 485 / 514 cases, W = 424.5 us
ppl = 9.8406 (corpus 173c87a5)
peak rss = 22828 MiB
load time = 10240 ms

## profile top shaders

- a1: mul_mat_subgroup_matrix_q8_0_f32_split4 24.1 ms (46.3%), RMS_NORM_MUL 14.0 ms (26.9%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 5.6 ms (10.8%)
- a2: mul_mat_vec_q8_0_f32_sg_reduce 119.7 ms (17.1%), RMS_NORM_MUL 110.4 ms (15.8%), flash_attn_vec_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_h_mask_blk_dsplit4 90.4 ms (12.9%)
- a3: mul_mat_subgroup_matrix_q4_0_f32 57.7 ms (42.2%), mul_mat_subgroup_matrix_q4_0_f32_split4 54.5 ms (39.8%), flash_attn_kf16_vf16_qf32_dstf32_mask_k_direct_v_direct_hsqk128_hsv128 7.4 ms (5.4%)
- a4: mul_mat_vec_q4_0_f32_add_residual_sg_reduce 264.9 ms (26.7%), mul_mat_vec_q4_0_f32_fuse_OP_SWIGLU_sg_reduce 175.8 ms (17.7%), quantize_q8_q4_0_sg_reduce 114.2 ms (11.5%)
- a5: mul_mat_id_subgroup_matrix_mxfp4_f32 436.0 ms (74.4%), mul_mat_subgroup_matrix_q8_0_f32_split4 37.5 ms (6.4%), flash_attn_kf16_vf16_qf32_dstf32_mask_sinks_k_direct_v_direct_hsqk64_hsv64 22.4 ms (3.8%)
- a6: mul_mat_id_vec_mxfp4_f32_sg_reduce 495.2 ms (31.9%), mul_mat_vec_q8_0_f32_add_residual_sg_reduce 256.8 ms (16.5%), mul_mat_vec_q8_0_f32_sg_reduce 125.1 ms (8.1%)
- g1: mul_mat_vec_q4_0_f32_add_residual_sg_reduce 263.9 ms (15.3%), mul_mat_subgroup_matrix_q4_0_f32 222.7 ms (12.9%), mul_mat_subgroup_matrix_q4_0_f32_split4 210.0 ms (12.2%)

