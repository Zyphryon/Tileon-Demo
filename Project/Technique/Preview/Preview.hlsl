// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Embedded://Shader/Color.hlsl"
#include "Embedded://Shader/Depth.hlsl"
#include "Resources://Technique/Common/Scene.hlsl"

struct fs_Input
{
    float4 Position : SV_POSITION;
    float2 Texture  : TEXCOORD0;
    float2 Probe    : TEXCOORD1;    // the pixel's clip-space coordinates
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(uint VertexID : SV_VertexID)
{
    const float4 Screen = ZyEmitScreen(VertexID);

    fs_Input Result;

    Result.Position = float4(Screen.xy, 0.0, 1.0);
    Result.Texture  = Screen.zw;
    Result.Probe    = Screen.xy;

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

Texture2D    t_Source : register(t0);
SamplerState s_Source : register(s0);

float4 main(fs_Input Input) : SV_Target0
{
#if defined(PREVIEW_NORMAL)

    return float4(ZyToGamma(t_Source.Sample(s_Source, Input.Texture).rgb), 1.0);

#elif defined(PREVIEW_DEPTH)

    const float  Depth     = t_Source.Sample(s_Source, Input.Texture).r;
    const float4 Probe     = mul(u_CameraInverse, float4(Input.Probe, ZyClipDepth(Depth), 1.0));
    const float  Elevation = saturate((Probe.y / Probe.w) / ELEVATION_SCALE);

    float3 Color = lerp(float3(0.12, 0.12, 0.12), float3(1.0, 1.0, 1.0), Elevation);

    return float4(ZyToGamma(Color * step(Depth, 0.99999)), 1.0);

#else

    float3 Scene = t_Source.Sample(s_Source, Input.Texture).rgb;

#ifdef    PREVIEW_GAMMA
    Scene = ZyToGamma(Scene);
#endif // PREVIEW_GAMMA

    return float4(Scene, 1.0);

#endif
}

#endif // FRAGMENT_SHADER