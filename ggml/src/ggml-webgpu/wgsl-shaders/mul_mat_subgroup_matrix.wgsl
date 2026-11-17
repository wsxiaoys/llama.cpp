diagnostic(off, chromium.subgroup_matrix_uniformity);
enable f16;
enable subgroups;
enable chromium_experimental_subgroup_matrix;

#define DECLARE_BYTE_LOADERS_SRC0
#ifdef SRC_OVERLAP
#define SRC0 merged_src
#define SRC1 merged_src
#endif
#include "common_decls.tmpl"

#include "mul_mat_decls.tmpl"

// TODO: this shader path does not work with some models like qwen2.5 on Metal devices, f16 accumulation causes NaNs.
// See https://github.com/ggml-org/llama.cpp/issues/21602

#ifdef VEC
fn store_dst(shmem_idx: u32, dst_idx: u32) {
    dst[dst_idx] = vec4<f32>(
        f32(shmem[shmem_idx]),
        f32(shmem[shmem_idx + 1]),
        f32(shmem[shmem_idx + 2]),
        f32(shmem[shmem_idx + 3])
    );
}
#endif

#ifdef SCALAR
fn store_dst(shmem_idx: u32, dst_idx: u32) {
    dst[dst_idx] = f32(shmem[shmem_idx]);
}
#endif

#ifdef MUL_MAT_ID
struct MulMatIdParams {
    offset_src0: u32,
    offset_src1: u32,
    offset_dst: u32,

    k: u32,
    m: u32,
    n_expert: u32,
    n_expert_used: u32,
    n_tokens: u32,
    b_ne1: u32,

    stride_01: u32,
    stride_11: u32,
    stride_02: u32,
    stride_12: u32,
};

// SRC0_TYPE and SRC1_TYPE are defined in mul_mat_decls, which is included
@group(0) @binding(0) var<storage, read_write> src0: array<SRC0_TYPE>; // [cols, rows, n_expert]
@group(0) @binding(1) var<storage, read_write> src1: array<SRC1_TYPE>; // [cols, b_ne1, n_tokens]
@group(0) @binding(2) var<storage, read_write> dst: array<DST_TYPE>;   // [rows, n_expert_used, n_tokens]

@group(0) @binding(3) var<storage, read_write> ids_slot_pos: array<u32>; // [n_expert_used * n_tokens]
@group(0) @binding(4) var<storage, read_write> ids_tiles: array<u32>; // [n_tiles, (expert, first slot, n slots) * n_tiles]

@group(0) @binding(5) var<uniform> params: MulMatIdParams;
#else
struct MulMatParams {
    offset_src0: u32,
    offset_src1: u32,
    offset_dst: u32,
    m: u32,
    n: u32,
    k: u32,
    stride_01: u32,
    stride_11: u32,
    stride_02: u32,
    stride_12: u32,
    stride_03: u32,
    stride_13: u32,
    bs02: u32,
    bs03: u32,
    broadcast2: u32,
    broadcast3: u32
};

// SRC0_TYPE and SRC1_TYPE are defined in mul_mat_decls, which is included
#ifdef SRC_OVERLAP
@group(0) @binding(0) var<storage, read_write> merged_src: array<SRC0_TYPE>;
#define DST_BINDING 1
#else
@group(0) @binding(0) var<storage, read_write> src0: array<SRC0_TYPE>; // M rows, K columns
@group(0) @binding(1) var<storage, read_write> src1: array<SRC1_TYPE>; // K rows, N columns (transposed)
#define DST_BINDING 2
#endif

@group(0) @binding(DST_BINDING) var<storage, read_write> dst: array<DST_TYPE>; // M rows, N columns (transposed)
@group(0) @binding(DST_BINDING + 1) var<uniform> params: MulMatParams;
#endif

const WG_M_SG_TILE_SIZE = SUBGROUP_M * SUBGROUP_MATRIX_M * SUBGROUP_MATRIX_M_SIZE;
const WG_N_SG_TILE_SIZE = SUBGROUP_N * SUBGROUP_MATRIX_N * SUBGROUP_MATRIX_N_SIZE;

// For portability we assume the max subgroup size, meaning some subgroups will be masked out if the
// runtime subgroup size is smaller.
const EXPECTED_SUBGROUPS = SUBGROUP_M * SUBGROUP_N;
const TOTAL_WORKGROUP_SIZE = SUBGROUP_M * SUBGROUP_N * MAX_SUBGROUP_SIZE;
const TILE_SRC0_SHMEM = TILE_K * SUBGROUP_M * SUBGROUP_MATRIX_M * SUBGROUP_MATRIX_M_SIZE;
const TILE_SRC1_SHMEM = TILE_K * SUBGROUP_N * SUBGROUP_MATRIX_N * SUBGROUP_MATRIX_N_SIZE;

const SG_MAT_ACCUM_SHMEM = SUBGROUP_M * SUBGROUP_MATRIX_M * SUBGROUP_N * SUBGROUP_MATRIX_N * SUBGROUP_MATRIX_M_SIZE * SUBGROUP_MATRIX_N_SIZE;

// We reuse shmem for accumulation matrices
const SHMEM_SIZE = max(TILE_SRC0_SHMEM + TILE_SRC1_SHMEM, SG_MAT_ACCUM_SHMEM);

var<workgroup> shmem: array<f16, SHMEM_SIZE>;

#ifdef MUL_MAT_ID
// per-slot (expert_used, token) of this expert tile, gathered from ids_slot_pos
var<workgroup> gathered_expert_used: array<u32, WG_N_SG_TILE_SIZE>;
var<workgroup> gathered_tokens: array<u32, WG_N_SG_TILE_SIZE>;

// the src1 columns of a slot tile belong to different tokens, so they are gathered per slot
fn init_shmem_id_src1(thread_id: u32, offset_src1: u32, rest_token_n: u32, k_outer: u32) {
    for (var elem_idx = thread_id * VEC_SIZE; elem_idx < TILE_SRC1_SHMEM; elem_idx += TOTAL_WORKGROUP_SIZE * VEC_SIZE) {
        let tile_n = elem_idx / TILE_K;
        let tile_k = elem_idx % TILE_K;
        if (tile_n < rest_token_n) {
            let global_src10 = k_outer + tile_k;
            let expert_used_idx = gathered_expert_used[tile_n] % params.b_ne1;
            let token_idx = gathered_tokens[tile_n];
            let src1_idx = offset_src1 + token_idx * params.stride_12 + expert_used_idx * params.stride_11 + global_src10;
            let src1_val = select(
                SRC1_TYPE(0.0),
                src1[src1_idx/VEC_SIZE],
                global_src10 < params.k);
            store_shmem(SHMEM_TYPE(src1_val), TILE_SRC0_SHMEM + elem_idx);
        } else {
            store_shmem(SHMEM_TYPE(0.0), TILE_SRC0_SHMEM + elem_idx);
        }
    }
}
#endif

#ifdef MUL_MAT_ID
@compute @workgroup_size(TOTAL_WORKGROUP_SIZE)
fn main(@builtin(workgroup_id) wg_id: vec3<u32>,
        @builtin(local_invocation_id) local_id: vec3<u32>,
        @builtin(subgroup_id) subgroup_id: u32,
        @builtin(num_workgroups) num_wg: vec3<u32>) {

    let thread_id = local_id.x;
    let subgroup_m = subgroup_id % SUBGROUP_M;
    let subgroup_n = subgroup_id / SUBGROUP_M;

    let wg_m_count = (params.m + WG_M_SG_TILE_SIZE - 1) / WG_M_SG_TILE_SIZE;
    let wg_linear = wg_id.y * num_wg.x + wg_id.x;

    // the slot tile of this workgroup, described by mul_mat_id_gather.wgsl
    let tile = wg_linear / wg_m_count;
    let wg_m = wg_linear % wg_m_count;

    let is_valid = tile < ids_tiles[0];

    var rest_token_n: u32 = 0;
    var src0_batch_offset: u32 = 0;

    if (is_valid) {
        let expert_idx = ids_tiles[1 + 3 * tile];
        let slot_base = ids_tiles[1 + 3 * tile + 1];
        rest_token_n = ids_tiles[1 + 3 * tile + 2];
        for (var i = thread_id; i < rest_token_n; i += TOTAL_WORKGROUP_SIZE) {
            let pos = ids_slot_pos[slot_base + i];
            gathered_expert_used[i] = pos % params.n_expert_used;
            gathered_tokens[i] = pos / params.n_expert_used;
        }
        src0_batch_offset = params.offset_src0 + expert_idx * params.stride_02;
    }

    workgroupBarrier();

    let offset_m = wg_m * WG_M_SG_TILE_SIZE;

    var acc_sg_mat : array<array<subgroup_matrix_result<f16, SUBGROUP_MATRIX_N_SIZE, SUBGROUP_MATRIX_M_SIZE>, SUBGROUP_MATRIX_N>, SUBGROUP_MATRIX_M>;

    for (var k_outer = 0u; k_outer < params.k; k_outer += TILE_K) {

        if (is_valid) {
            // see mul_mat_decls.tmpl
            init_shmem_src0(thread_id, src0_batch_offset, offset_m, k_outer);
            init_shmem_id_src1(thread_id, params.offset_src1, rest_token_n, k_outer);
        }

        workgroupBarrier();

        if (is_valid && subgroup_id < EXPECTED_SUBGROUPS) {

            for (var k_inner = 0u; k_inner < TILE_K; k_inner += SUBGROUP_MATRIX_K_SIZE) {

                let src0_shmem_idx_base = subgroup_m * SUBGROUP_MATRIX_M * SUBGROUP_MATRIX_M_SIZE * TILE_K + k_inner;
                var src0_sg_mats: array<subgroup_matrix_left<f16, SUBGROUP_MATRIX_K_SIZE, SUBGROUP_MATRIX_M_SIZE>, SUBGROUP_MATRIX_M>;
                for (var m = 0u; m < SUBGROUP_MATRIX_M; m++) {
                    src0_sg_mats[m] = subgroupMatrixLoad<subgroup_matrix_left<f16, SUBGROUP_MATRIX_K_SIZE, SUBGROUP_MATRIX_M_SIZE>>(
                        &shmem,
                        src0_shmem_idx_base + m * SUBGROUP_MATRIX_M_SIZE * TILE_K,
                        false,
                        TILE_K
                    );
                }

                let src1_shmem_idx_base = TILE_SRC0_SHMEM + subgroup_n * SUBGROUP_MATRIX_N * SUBGROUP_MATRIX_N_SIZE * TILE_K + k_inner;
                for (var n = 0u; n < SUBGROUP_MATRIX_N; n++) {
                    let src1_sg_mat = subgroupMatrixLoad<subgroup_matrix_right<f16, SUBGROUP_MATRIX_N_SIZE, SUBGROUP_MATRIX_K_SIZE>>(
                        &shmem,
                        src1_shmem_idx_base + n * SUBGROUP_MATRIX_N_SIZE * TILE_K,
                        true,
                        TILE_K
                    );
                    for (var m = 0u; m < SUBGROUP_MATRIX_M; m++) {
                        acc_sg_mat[m][n] = subgroupMatrixMultiplyAccumulate(src0_sg_mats[m], src1_sg_mat, acc_sg_mat[m][n]);
                    }
                }
            }
        }

        workgroupBarrier();
    }

    // Stage the subgroup matrix tiles into shared memory
    let WG_TILE_STRIDE = WG_M_SG_TILE_SIZE;
    let tile_row_base_local = subgroup_n * SUBGROUP_MATRIX_N * SUBGROUP_MATRIX_N_SIZE;
    let tile_col_base_local = subgroup_m * SUBGROUP_MATRIX_M * SUBGROUP_MATRIX_M_SIZE;

    if (subgroup_id < EXPECTED_SUBGROUPS) {
        for (var n = 0u; n < SUBGROUP_MATRIX_N; n++) {
            for (var m = 0u; m < SUBGROUP_MATRIX_M; m++) {
                let local_row = tile_row_base_local + n * SUBGROUP_MATRIX_N_SIZE;
                let local_col = tile_col_base_local + m * SUBGROUP_MATRIX_M_SIZE;
                let out_base = local_row * WG_TILE_STRIDE + local_col;
                subgroupMatrixStore(&shmem, out_base, acc_sg_mat[m][n], true, WG_TILE_STRIDE);
            }
        }
    }

    workgroupBarrier();

    // Scatter the workgroup tile into dst[token, expert_used, :]
    if (is_valid) {
        let total_tile_elems = WG_N_SG_TILE_SIZE * WG_M_SG_TILE_SIZE;
        let dst2_stride = params.m * params.n_expert_used;
        for (var idx = thread_id * VEC_SIZE; idx < total_tile_elems; idx += TOTAL_WORKGROUP_SIZE * VEC_SIZE) {
            let local_m = idx % WG_TILE_STRIDE;
            let local_n = idx / WG_TILE_STRIDE;

            let global_row = wg_m * WG_M_SG_TILE_SIZE + local_m;

            if (local_n < rest_token_n && global_row < params.m) {
                let expert_used_idx = gathered_expert_used[local_n];
                let token_idx = gathered_tokens[local_n];
                let dst_idx = params.offset_dst + token_idx * dst2_stride + expert_used_idx * params.m + global_row;
                store_dst(idx, dst_idx/VEC_SIZE);
            }
        }
    }
}
#else
@compute @workgroup_size(TOTAL_WORKGROUP_SIZE)
fn main(@builtin(workgroup_id) wg_id: vec3<u32>,
        @builtin(local_invocation_id) local_id: vec3<u32>,
        @builtin(subgroup_id) subgroup_id: u32,
        @builtin(num_workgroups) num_wg: vec3<u32>) {

    let thread_id = local_id.x;
    let subgroup_m = subgroup_id % SUBGROUP_M;
    let subgroup_n = subgroup_id / SUBGROUP_M;

    let wg_m_count = (params.m + WG_M_SG_TILE_SIZE - 1) / WG_M_SG_TILE_SIZE;
    let wg_n_count = (params.n + WG_N_SG_TILE_SIZE - 1) / WG_N_SG_TILE_SIZE;
    let wg_per_matrix = wg_m_count * wg_n_count;

    let wg_linear = wg_id.y * num_wg.x + wg_id.x;

    let batch_idx = wg_linear / wg_per_matrix;

    let total_batches = params.bs02 * params.broadcast2 * params.bs03 * params.broadcast3;
    if (batch_idx >= total_batches) {
        return;
    }

    let wg_in_batch = wg_linear % wg_per_matrix;
    let wg_m = wg_in_batch % wg_m_count;
    let wg_n = wg_in_batch / wg_m_count;

    let dst2_stride = params.m * params.n;
    let dst3_stride = dst2_stride * params.bs02 * params.broadcast2;

    let dst3_idx = batch_idx / (params.bs02 * params.broadcast2);
    let src03_idx = dst3_idx / params.broadcast3;
    let src13_idx = dst3_idx;
    let dst2_idx = batch_idx % (params.bs02 * params.broadcast2);
    let src02_idx = dst2_idx / params.broadcast2;
    let src12_idx = dst2_idx;

    let src0_batch_offset = params.offset_src0 + src03_idx * params.stride_03 + src02_idx * params.stride_02;
    let src1_batch_offset = params.offset_src1 + src13_idx * params.stride_13 + src12_idx * params.stride_12;

    let offset_m = wg_m * SUBGROUP_M * SUBGROUP_MATRIX_M * SUBGROUP_MATRIX_M_SIZE;
    let offset_n = wg_n * SUBGROUP_N * SUBGROUP_MATRIX_N * SUBGROUP_MATRIX_N_SIZE;

    var acc_sg_mat : array<array<subgroup_matrix_result<f16, SUBGROUP_MATRIX_N_SIZE, SUBGROUP_MATRIX_M_SIZE>, SUBGROUP_MATRIX_N>, SUBGROUP_MATRIX_M>;

    for (var k_outer = 0u; k_outer < params.k; k_outer += TILE_K) {

        // see mul_mat_decls.tmpl
        init_shmem_src0(thread_id, src0_batch_offset, offset_m, k_outer);
        init_shmem_src1(thread_id, src1_batch_offset, offset_n, k_outer);

        workgroupBarrier();

        if (subgroup_id < EXPECTED_SUBGROUPS) {

            for (var k_inner = 0u; k_inner < TILE_K; k_inner += SUBGROUP_MATRIX_K_SIZE) {

                let src0_shmem_idx_base = subgroup_m * SUBGROUP_MATRIX_M * SUBGROUP_MATRIX_M_SIZE * TILE_K + k_inner;
                var src0_sg_mats: array<subgroup_matrix_left<f16, SUBGROUP_MATRIX_K_SIZE, SUBGROUP_MATRIX_M_SIZE>, SUBGROUP_MATRIX_M>;
                for (var m = 0u; m < SUBGROUP_MATRIX_M; m++) {
                    src0_sg_mats[m] = subgroupMatrixLoad<subgroup_matrix_left<f16, SUBGROUP_MATRIX_K_SIZE, SUBGROUP_MATRIX_M_SIZE>>(
                        &shmem,
                        src0_shmem_idx_base + m * SUBGROUP_MATRIX_M_SIZE * TILE_K,
                        false,
                        TILE_K
                    );
                }

                let src1_shmem_idx_base = TILE_SRC0_SHMEM + subgroup_n * SUBGROUP_MATRIX_N * SUBGROUP_MATRIX_N_SIZE * TILE_K + k_inner;
                for (var n = 0u; n < SUBGROUP_MATRIX_N; n++) {
                    let src1_sg_mat = subgroupMatrixLoad<subgroup_matrix_right<f16, SUBGROUP_MATRIX_N_SIZE, SUBGROUP_MATRIX_K_SIZE>>(
                        &shmem,
                        src1_shmem_idx_base + n * SUBGROUP_MATRIX_N_SIZE * TILE_K,
                        true,
                        TILE_K
                    );
                    for (var m = 0u; m < SUBGROUP_MATRIX_M; m++) {
                        acc_sg_mat[m][n] = subgroupMatrixMultiplyAccumulate(src0_sg_mats[m], src1_sg_mat, acc_sg_mat[m][n]);
                    }
                }
            }
        }

        workgroupBarrier();
    }

    let dst_batch_offset = params.offset_dst + dst3_idx * dst3_stride + dst2_idx * dst2_stride;

    // Stage the subgroup matrix tiles into shared memory
    // This uses WG_M_SG_TILE_SIZE as the stride (number of columns in the workgroup tile).
    let WG_TILE_STRIDE = WG_M_SG_TILE_SIZE;
    let tile_row_base_local = subgroup_n * SUBGROUP_MATRIX_N * SUBGROUP_MATRIX_N_SIZE;
    let tile_col_base_local = subgroup_m * SUBGROUP_MATRIX_M * SUBGROUP_MATRIX_M_SIZE;

    if (subgroup_id < EXPECTED_SUBGROUPS) { // 2-5% performance hit :(
        for (var n = 0u; n < SUBGROUP_MATRIX_N; n++) {
            for (var m = 0u; m < SUBGROUP_MATRIX_M; m++) {
                let local_row = tile_row_base_local + n * SUBGROUP_MATRIX_N_SIZE;
                let local_col = tile_col_base_local + m * SUBGROUP_MATRIX_M_SIZE;
                let out_base = local_row * WG_TILE_STRIDE + local_col;
                subgroupMatrixStore(&shmem, out_base, acc_sg_mat[m][n], true, WG_TILE_STRIDE);
            }
        }
    }

    workgroupBarrier();

    // Cooperative write: iterate over the entire workgroup tile
    let tile_rows = WG_N_SG_TILE_SIZE;
    let tile_cols = WG_M_SG_TILE_SIZE;
    let total_tile_elems = tile_rows * tile_cols;
    let tile_dst_row_base = wg_m * SUBGROUP_M * SUBGROUP_MATRIX_M * SUBGROUP_MATRIX_M_SIZE;
    let tile_dst_col_base = wg_n * SUBGROUP_N * SUBGROUP_MATRIX_N * SUBGROUP_MATRIX_N_SIZE;

    for (var idx = thread_id * VEC_SIZE; idx < total_tile_elems; idx += TOTAL_WORKGROUP_SIZE * VEC_SIZE) {
        let local_row = idx % WG_TILE_STRIDE;
        let local_col = idx / WG_TILE_STRIDE;

        let global_row = tile_dst_row_base + local_row;
        let global_col = tile_dst_col_base + local_col;

        if (global_col < params.n && global_row < params.m) {
            let dst_idx = dst_batch_offset + global_col * params.m + global_row;
            store_dst(idx, dst_idx/VEC_SIZE);
        }
    }
}
#endif
