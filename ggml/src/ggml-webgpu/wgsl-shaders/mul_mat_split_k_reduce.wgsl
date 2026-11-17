// Sums the partial tiles written by the split-K dense subgroup matrix path.
// The partials are laid out like dst and concatenated, so split s covers [s*ne, (s+1)*ne).

@group(0) @binding(0)
var<storage, read_write> partial: array<f32>;

@group(0) @binding(1)
var<storage, read_write> dst: array<f32>;

struct Params {
    ne: u32,         // output elements, also the stride between two partials
    split_k: u32,    // number of partials
    offset_dst: u32, // in elements
};

@group(0) @binding(2)
var<uniform> params: Params;

@compute @workgroup_size(WG_SIZE)
fn main(@builtin(global_invocation_id) gid: vec3<u32>,
        @builtin(num_workgroups) num_wg: vec3<u32>) {

    let i = gid.x + gid.y * num_wg.x * WG_SIZE;
    if (i >= params.ne) {
        return;
    }

    var acc: f32 = 0.0;
    for (var s = 0u; s < params.split_k; s++) {
        acc += partial[s * params.ne + i];
    }

    dst[params.offset_dst + i] = acc;
}
