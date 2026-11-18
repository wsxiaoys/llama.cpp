// Fused {RMS_NORM, MUL, ROPE}: the per-head QK norm and the rotation in one dispatch.
//
// One workgroup per row and WG_SIZE >= ne0, so every thread owns exactly one element of the row:
// the normed row is staged in scratch and the rotation reads its pair from there, so the row never
// round-trips through global memory.
//
// Guards enforced by ggml_webgpu_can_fuse_rms_norm_mul_rope: f32/contiguous-rows operands,
// rope->src[2] == nullptr, n_dims == ne0, n_offs == 0, mode in {NORMAL, NEOX}, ne0 even and
// wg_size >= ne0.

struct Params {
    offset_rn_src: u32,
    offset_mul_src: u32,
    offset_src1: u32,
    offset_dst: u32,

    stride_rn_src1: u32,
    stride_rn_src2: u32,
    stride_rn_src3: u32,

    stride_mul_src1: u32,
    stride_mul_src2: u32,
    stride_mul_src3: u32,

    stride_dst1: u32,
    stride_dst2: u32,
    stride_dst3: u32,

    mul_src_ne0: u32,
    mul_src_ne1: u32,
    mul_src_ne2: u32,
    mul_src_ne3: u32,

    ne0: u32,
    ne1: u32,
    ne2: u32,
    ne3: u32,

    eps: f32,

    mode: u32,
    theta_scale: f32,
    attn_factor: f32,
    freq_scale: f32,
    ext_factor: f32,
    corr_dim0: f32,
    corr_dim1: f32
};

@group(0) @binding(0)
var<storage, read_write> rn_src: array<f32>;

@group(0) @binding(1)
var<storage, read_write> mul_src: array<f32>;

@group(0) @binding(2)
var<storage, read_write> pos: array<i32>;

@group(0) @binding(3)
var<storage, read_write> dst: array<f32>;

@group(0) @binding(4)
var<uniform> params: Params;

var<workgroup> scratch: array<f32, WG_SIZE>;

// verbatim from rope.wgsl
fn rope_yarn_ramp(low: f32, high: f32, i: u32) -> f32 {
    let y = (f32(i / 2) - low) / max(0.001f, high - low);
    return 1.0f - min(1.0f, max(0.0f, y));
}

// verbatim from rope.wgsl
fn rope_yarn(theta_extrap: f32, i: u32) -> vec2<f32> {
    var mscale = params.attn_factor;
    var theta  = params.freq_scale * theta_extrap;
    if (params.ext_factor != 0.0f) {
        let ramp_mix = rope_yarn_ramp(params.corr_dim0, params.corr_dim1, i) * params.ext_factor;
        theta = theta * (1 - ramp_mix) + theta_extrap * ramp_mix;
        mscale *= 1.0f + 0.1f * log(1.0f / params.freq_scale);
    }
    return vec2<f32>(cos(theta) * mscale, sin(theta) * mscale);
}

@compute @workgroup_size(WG_SIZE)
fn main(@builtin(workgroup_id) wid: vec3<u32>,
        @builtin(num_workgroups) num_wg: vec3<u32>,
        @builtin(local_invocation_id) lid: vec3<u32>) {

    // one workgroup per row
    var i = wid.x + wid.y * num_wg.x;
    if (i >= params.ne1 * params.ne2 * params.ne3) {
        return;
    }
    let i3 = i / (params.ne2 * params.ne1);
    i = i % (params.ne2 * params.ne1);
    let i2 = i / params.ne1;
    let i1 = i % params.ne1;
    let i_rn_src_row = params.offset_rn_src + i3 * params.stride_rn_src3 + i2 * params.stride_rn_src2 + i1 * params.stride_rn_src1;
    let i_mul_src_row = params.offset_mul_src + (i3 % params.mul_src_ne3) * params.stride_mul_src3 + (i2 % params.mul_src_ne2) * params.stride_mul_src2 + (i1 % params.mul_src_ne1) * params.stride_mul_src1;
    let i_dst_row = params.offset_dst + i3 * params.stride_dst3 + i2 * params.stride_dst2 + i1 * params.stride_dst1;

    // one element per thread: wg_size >= ne0
    var sum = 0.0f;
    if (lid.x < params.ne0) {
        sum = pow(rn_src[i_rn_src_row + lid.x], 2.0);
    }
    scratch[lid.x] = sum;

    workgroupBarrier();

    var offset: u32 = WG_SIZE / 2;
    while (offset > 0) {
        if (lid.x < offset) {
            scratch[lid.x] += scratch[lid.x + offset];
        }
        offset = offset / 2;
        workgroupBarrier();
    }
    sum = scratch[0];
    // scratch is reused for the normed row
    workgroupBarrier();

    let scale = 1.0/sqrt(sum/f32(params.ne0) + params.eps);

    if (lid.x < params.ne0) {
        scratch[lid.x] = scale * rn_src[i_rn_src_row + lid.x] * mul_src[i_mul_src_row + lid.x % params.mul_src_ne0];
    }
    workgroupBarrier();

    // one thread per rotated pair; the pair partner is in the same row and therefore in scratch
    if (lid.x >= params.ne0 / 2) {
        return;
    }
    let is_neox = (params.mode & 2) != 0;
    let i0 = 2 * lid.x;
    let iw = i0;  // n_offs == 0
    let theta_base = f32(pos[params.offset_src1 + i2]) * pow(params.theta_scale, f32(iw / 2));
    let thetas = rope_yarn(theta_base, iw);

    let pair_offset = select(1u, params.ne0 / 2, is_neox);
    let i_pair = select(i0, lid.x, is_neox);
    let x0 = scratch[i_pair];
    let x1 = scratch[i_pair + pair_offset];
    dst[i_dst_row + i_pair] = x0 * thetas.x - x1 * thetas.y;
    dst[i_dst_row + i_pair + pair_offset] = x0 * thetas.y + x1 * thetas.x;
}
