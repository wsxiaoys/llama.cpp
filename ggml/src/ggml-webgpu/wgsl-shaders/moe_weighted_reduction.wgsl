// Fused MoE expert weighted reduction: out[row, tok] = sum_e weights[e, tok] * experts[row, e, tok].
// Replaces the MUL + n_expert_used VIEWs + n_expert_used-1 ADDs of build_moe_ffn.

const MAX_EXPERTS: u32 = 32u;

struct Params {
    offset_experts: u32,
    offset_weights: u32,
    offset_dst: u32,

    nb_e1: u32,
    nb_e2: u32,
    nb_w1: u32,
    nb_w2: u32,

    n_embd: u32,
    n_expert_used: u32,
    n_tokens: u32,
};

@group(0) @binding(0) var<storage, read_write> experts: array<f32>; // [n_embd, n_expert_used, n_tokens]
@group(0) @binding(1) var<storage, read_write> weights: array<f32>; // [1, n_expert_used, n_tokens]
@group(0) @binding(2) var<storage, read_write> dst: array<f32>; // [n_embd, n_tokens]
@group(0) @binding(3) var<uniform> params: Params;

@compute @workgroup_size(WG_SIZE)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let i = gid.x;
    if (i >= params.n_embd * params.n_tokens) {
        return;
    }

    let row = i % params.n_embd;
    let tok = i / params.n_embd;

    let experts_row = params.offset_experts + row + tok * params.nb_e2;
    let weights_row = params.offset_weights + tok * params.nb_w2;

    // the products go through a local array so they stay rounded; contracting the multiply into
    // the accumulator (FMA) changes the result by an ulp and moves MoE PPL
    var prod: array<f32, MAX_EXPERTS>;
    for (var e: u32 = 0u; e < params.n_expert_used; e += 1u) {
        prod[e] = weights[weights_row + e * params.nb_w1] * experts[experts_row + e * params.nb_e1];
    }

    var acc: f32 = prod[0];
    for (var e: u32 = 1u; e < params.n_expert_used; e += 1u) {
        acc = acc + prod[e];
    }

    dst[params.offset_dst + i] = acc;
}
