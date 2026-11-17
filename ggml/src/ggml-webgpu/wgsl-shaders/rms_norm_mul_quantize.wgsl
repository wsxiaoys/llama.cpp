enable subgroups;
enable f16;

requires packed_4x8_integer_dot_product;

#include "common_decls.tmpl"

// Fused full-width RMS_NORM+MUL followed by the MMVQ q8_1 quantize. The matcher guarantees the MUL
// result is one row consumed only by MMVQ MUL_MATs, so the norm reduction and the activation's
// q8_1 copy are produced by one dispatch into the E001 cache slot.
struct Params {
    offset_rn: u32,
    offset_mul: u32,
    ne0: u32,
    eps: f32,
};

@group(0) @binding(0) var<storage, read_write> rn_src: array<f32>;
@group(0) @binding(1) var<storage, read_write> mul_src: array<f32>;
@group(0) @binding(2) var<storage, read_write> src1q: array<q8_1>;
@group(0) @binding(3) var<uniform> params: Params;

var<workgroup> scratch: array<f32, WG_SIZE>;

fn cluster_max_8(v: f32) -> f32 {
    var r = v;
    r = max(r, subgroupShuffleXor(r, 1u));
    r = max(r, subgroupShuffleXor(r, 2u));
    r = max(r, subgroupShuffleXor(r, 4u));
    return r;
}

fn cluster_add_i4x8(v: i32) -> i32 {
    var r = v;
    r += subgroupShuffleXor(r, 1u);
    r += subgroupShuffleXor(r, 2u);
    r += subgroupShuffleXor(r, 4u);
    return r;
}

@compute @workgroup_size(WG_SIZE)
fn main(
    @builtin(local_invocation_id) local_id: vec3<u32>,
    @builtin(workgroup_id) wg_id: vec3<u32>,
    @builtin(num_workgroups) num_wg: vec3<u32>
) {
    let thread_id = local_id.x;

    let ne0_vec4   = params.ne0 / 4u;
    let wg_per_vec = (ne0_vec4 + (WG_SIZE - 1u)) / WG_SIZE;

    let wg_linear = wg_id.y * num_wg.x + wg_id.x;
    if (wg_linear >= wg_per_vec) {
        return;
    }
    let src11_wg_idx = wg_linear;

    // row sum of squares, same order as rms_norm_mul.wgsl
    let elems = (params.ne0 + WG_SIZE - 1u) / WG_SIZE;
    var sum = 0.0f;
    var col = thread_id;
    for (var j: u32 = 0; j < elems; j++) {
        if (col >= params.ne0) {
            break;
        }
        sum += pow(rn_src[params.offset_rn + col], 2.0);
        col += WG_SIZE;
    }

    scratch[thread_id] = sum;

    workgroupBarrier();

    var offset = WG_SIZE / 2u;
    while (offset > 0u) {
        if (thread_id < offset) {
            scratch[thread_id] += scratch[thread_id + offset];
        }
        offset = offset / 2u;
        workgroupBarrier();
    }

    let scale = 1.0 / sqrt(scratch[0] / f32(params.ne0) + params.eps);

    // y = scale * x * w, quantized one 32-element block per 8 lanes
    let blocks_per_wg = (WG_SIZE * 4u) / 32u;
    let src1q_idx     = src11_wg_idx * blocks_per_wg + thread_id / 8u;
    let qs_idx        = thread_id % 8u;

    let src11_vec4_idx = src11_wg_idx * WG_SIZE + thread_id;
    let is_valid       = src11_vec4_idx < ne0_vec4;

    var q4         = vec4<f32>(0.0);
    var q4_quants  = 0u;
    var thread_amax = 0.0;

    if (is_valid) {
        let base  = params.offset_rn + src11_vec4_idx * 4u;
        let mbase = params.offset_mul + src11_vec4_idx * 4u;
        q4 = vec4<f32>(
            scale * rn_src[base + 0u] * mul_src[mbase + 0u],
            scale * rn_src[base + 1u] * mul_src[mbase + 1u],
            scale * rn_src[base + 2u] * mul_src[mbase + 2u],
            scale * rn_src[base + 3u] * mul_src[mbase + 3u]);
        let abs_q4 = abs(q4);
        thread_amax = max(max(abs_q4[0], abs_q4[1]), max(abs_q4[2], abs_q4[3]));
    }

    let d = cluster_max_8(thread_amax) / 127.0;

    if (is_valid) {
        let id = select(0.0, 1.0 / d, d > 0.0);
        q4_quants = pack4xI8(vec4<i32>(round(q4 * id)));
        if (qs_idx == 0u) {
            src1q[src1q_idx].d = f16(d);
        }
        src1q[src1q_idx].qs[qs_idx] = q4_quants;
    }

    // always write s: the slot may be shared by consumers whose dequant needs it
    let q4_quants_sum = dot4I8Packed(q4_quants, 0x01010101u);
    let s = f16(d * f32(cluster_add_i4x8(q4_quants_sum)));
    if (is_valid) {
        if (qs_idx == 0u) {
            src1q[src1q_idx].s = s;
        }
    }
}
