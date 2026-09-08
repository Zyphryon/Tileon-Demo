// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Embedded://Shader/Font.hlsl"
#include "Resources://Technique/Common/Scene.hlsl"
#include "Embedded://Shader/Affine.hlsl"

cbuffer cb_Material : register(b2)
{
    float2 u_Range;
};

cbuffer cb_Instance : register(b3)
{
    struct PackedFontParameters
    {
        float4       u_Transform0;
        float4       u_Transform1;
        float4       u_Transform2;
        ZyFontEffect u_Effect;
    };
    PackedFontParameters u_Parameters[128];
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Attributes
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

struct vs_Input
{
    uint     VertexID   : SV_VertexID;

    float4   Frame      : SLOT0;  // normalized atlas edges: minimum.xy, maximum.xy
    int2     Offset     : SLOT1;  // corner within the text layout, in subpixel steps
    uint2    Size       : SLOT2;  // extent, in subpixel steps
    uint     Effect     : SLOT3;  // the interned run slot
    float4   Color      : SLOT4;
};

struct fs_Input
{
    float4               Position : SV_POSITION;
    float2               Texture  : TEXCOORD0;
    float4               Color    : COLOR0;
    nointerpolation uint Effect   : TEXCOORD1;
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(vs_Input Input)
{
    const float2 Corner = ZyEmitRect(Input.VertexID);

    const PackedFontParameters Run = u_Parameters[Input.Effect];

    const float2   Plane     = (float2(Input.Offset) + Corner * float2(Input.Size)) * GLYPH_SUBPIXEL;
    const ZyAffine Transform = ZyReadAffine(Run.u_Transform0, Run.u_Transform1, Run.u_Transform2);
    const float3   Position  = ZyApplyAffine(Transform, float3(Plane, 0.0));

    fs_Input Result;

    Result.Position = mul(u_Camera, float4(Position, 1.0));
    Result.Texture  = lerp(Input.Frame.xy, Input.Frame.zw, Corner);
    Result.Color    = Input.Color;
    Result.Effect   = Input.Effect;

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

Texture2D    t_Albedo : register(t0);
SamplerState s_Albedo : register(s0);

float4 main(fs_Input Input) : SV_Target
{
    const PackedFontParameters Font = u_Parameters[Input.Effect];

    const float4 Sample = t_Albedo.Sample(s_Albedo, Input.Texture);
    const float  Spread = ZyFontSpread(Input.Texture, u_Range);

    return ZyFontShade(Font.u_Effect, Sample, Spread, Input.Color);
}

#endif // FRAGMENT_SHADER