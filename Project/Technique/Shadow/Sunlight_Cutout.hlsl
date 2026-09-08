// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"

cbuffer cb_Pass : register(b1)
{
    float4x4 u_Sunlight;    // Turns world space into the sun's own clip space.
};

struct vs_Input
{
    uint   VertexID : SV_VertexID;

    float4 Origin   : SLOT0;    // where the quad rises from, with the cutoff its art is cut at in w
    float4 SpanU    : SLOT1;    // the run across the quad, with the layer of a layered material in w
    float4 SpanV    : SLOT2;    // the rise up the quad, with w unused
    float4 Frame    : SLOT3;    // the art's crop, with any mirroring already turned into the endpoints
};

struct fs_Input
{
    float4                 Position : SV_POSITION;
    float2                 Texture  : TEXCOORD0;    // the texel of the art the quad is cut out by
    nointerpolation float  Cutoff   : TEXCOORD1;    // the alpha under which a texel is no blocker
#ifdef ENABLE_LAYERED
    nointerpolation float  Layer    : TEXCOORD2;    // the layer of the material's array the art is read from
#endif
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(vs_Input Input)
{
    fs_Input Result;

    const float2 Corner   = ZyEmitRect(Input.VertexID);
    const float3 Position = Input.Origin.xyz + Corner.x * Input.SpanU.xyz + Corner.y * Input.SpanV.xyz;

    Result.Position = mul(u_Sunlight, float4(Position, 1.0));
    Result.Texture  = lerp(Input.Frame.xy, Input.Frame.zw, Corner);
    Result.Cutoff   = Input.Origin.w;
#ifdef ENABLE_LAYERED
    Result.Layer    = Input.SpanU.w;
#endif

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

#ifdef ENABLE_LAYERED
Texture2DArray t_Albedo : register(t0);
#else
Texture2D      t_Albedo : register(t0);
#endif
SamplerState s_Albedo : register(s0);

/// The map keeps the nearest blocker, which the depth test settles once the cutout is carved away.
void main(fs_Input Input)
{
#ifdef ENABLE_LAYERED
    clip(t_Albedo.Sample(s_Albedo, float3(Input.Texture, Input.Layer)).a - Input.Cutoff);
#else
    clip(t_Albedo.Sample(s_Albedo, Input.Texture).a - Input.Cutoff);
#endif
}

#endif // FRAGMENT_SHADER