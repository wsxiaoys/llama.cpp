enable f16;

#ifdef TYPE_F32
#define DataType f32
#endif
#ifdef TYPE_F16
#define DataType f16
#endif

#include "glu_op.tmpl"

struct Params {
    offset_src0: u32,
    offset_src1: u32,
    offset_dst: u32,

    // Strides (in elements)
    stride_src01: u32,
    stride_src02: u32,
    stride_src03: u32,

    stride_src11: u32,
    stride_src12: u32,
    stride_src13: u32,

    stride_dst1: u32,
    stride_dst2: u32,
    stride_dst3: u32,

    // shape of dst
    ne: u32,
    ne0: u32,
    ne1: u32,
    ne2: u32,

    swapped: u32,
    alpha: f32,
    limit: f32,
}

@group(0) @binding(0)
var<storage, read_write> src0: array<DataType>;

#ifdef SRC_OVERLAP
@group(0) @binding(1)
var<storage, read_write> dst: array<DataType>;

@group(0) @binding(2)
var<uniform> params: Params;

fn a_value(base: u32) -> DataType {
    return src0[base];
}

fn b_value(base: u32) -> DataType {
    return src0[base];
}

#elif defined(NO_SPLIT)
@group(0) @binding(1)
var<storage, read_write> dst: array<DataType>;

@group(0) @binding(2)
var<uniform> params: Params;

fn a_value(base: u32) -> DataType {
    let offset: u32 = select(0, params.ne0, params.swapped != 0);
    return src0[base + offset];
}

fn b_value(base: u32) -> DataType {
    let offset: u32 = select(params.ne0, 0, params.swapped != 0);
    return src0[base + offset];
}

#else
@group(0) @binding(1)
var<storage, read_write> src1: array<DataType>;

@group(0) @binding(2)
var<storage, read_write> dst: array<DataType>;

@group(0) @binding(3)
var<uniform> params: Params;

fn a_value(base: u32) -> DataType {
    return src0[base];
}

fn b_value(base: u32) -> DataType {
    return src1[base];
}

#endif

@compute @workgroup_size(WG_SIZE)
fn main(@builtin(num_workgroups) num_wg: vec3<u32>,
        @builtin(global_invocation_id) gid: vec3<u32>) {

    let gid_i = gid.x + (num_wg.x * u32(WG_SIZE)) * gid.y;
    if (gid_i >= params.ne) {
        return;
    }

    var i = gid_i;
    let i3 = i / (params.ne2 * params.ne1 * params.ne0);
    i = i % (params.ne2 * params.ne1 * params.ne0);
    let i2 = i / (params.ne1 * params.ne0);
    i = i % (params.ne1 * params.ne0);
    let i1 = i / params.ne0;
    let i0 = i % params.ne0;

    let i_a = params.offset_src0 + i3 * params.stride_src03 + i2 * params.stride_src02 + i1 * params.stride_src01 + i0;
    let i_b = params.offset_src1 + i3 * params.stride_src13 + i2 * params.stride_src12 + i1 * params.stride_src11 + i0;
    let i_dst = params.offset_dst + i3 * params.stride_dst3 + i2 * params.stride_dst2 + i1 * params.stride_dst1 + i0;

    dst[i_dst] = glu_op(a_value(i_a), b_value(i_b));
}
