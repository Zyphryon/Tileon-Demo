// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"

cbuffer cb_Pass : register(b1)
{
    float4x4 u_Sunlight;    // Turns world space into the sun's own clip space.
    float4   u_Toward;      // The direction the sun stands in, of unit length, with w unused.
};

static const float kCardCutoff = 0.35;
static const float kCardLift   = 0.15;

struct vs_Input
{
    uint   VertexID : SV_VertexID;

    float4 Center   : SLOT0;    // the anchor the art stands on, with w unused
    float4 Size     : SLOT1;    // how wide and tall the art stands, with zw unused
    float4 Frame    : SLOT2;    // the art's crop within the sheet it is packed in
};

struct fs_Input
{
    float4 Position : SV_POSITION;
    float2 Texture  : TEXCOORD0;
    float  Along    : TEXCOORD1;    // how far along the sun the card stands, over the map's own span
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(vs_Input Input)
{
    fs_Input Result;

    const float2 Corner = ZyEmitRect(Input.VertexID);
    const float3 Toward = u_Toward.xyz;

    const float3 Leaning = float3(0.0, 1.0, 0.0) - Toward * Toward.y;
    const float3 Raised  = (dot(Leaning, Leaning) > 1e-6) ? normalize(Leaning) : float3(0.0, 0.0, 1.0);
    const float3 Right   = normalize(cross(Toward, Raised));
    const float3 Footing = Input.Center.xyz + float3(0.0, Input.Size.y * kCardLift, 0.0);

    const float3 Position = Footing
                          + Right  * ((Corner.x - 0.5) * Input.Size.x)
                          + Raised * (Corner.y * Input.Size.y);

    const float4 Clip = mul(u_Sunlight, float4(Position, 1.0));

    Result.Position = Clip;
    Result.Along    = Clip.z;
    Result.Texture  = lerp(Input.Frame.xy, Input.Frame.zw, float2(Corner.x, 1.0 - Corner.y));

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

Texture2D    t_Albedo : register(t0);
SamplerState s_Albedo : register(s0);

float main(fs_Input Input) : SV_Target0
{
    clip(t_Albedo.Sample(s_Albedo, Input.Texture).a - kCardCutoff);

    return saturate(Input.Along);
}

#endif // FRAGMENT_SHADER
