// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Embedded://Shader/Packing.hlsl"
#include "Embedded://Shader/Depth.hlsl"
#include "Resources://Technique/Common/Scene.hlsl"

cbuffer cb_Pass : register(b1)
{
    float4   u_SunColor;    // RGB = Color * Intensity * Headroom, A = Sun Direction X
    float4   u_SkyColor;    // RGB = Color * Intensity * Headroom, A = Sun Direction Y
    float4   u_GroundColor; // RGB = Color * Intensity * Headroom, A = Sun Direction Z
    float4x4 u_Sunlight;    // Turns world space into the sun's clip space, which its map is read through
    float4   u_Sunstep;     // XY = what one texel of that map covers, ZW unused
};

/// How far a surface is let off the map before it is taken to be standing in its own shadow.
static const float kSunBias = 0.0015;

struct fs_Input
{
    float4 Position : SV_POSITION;
    float2 Probe    : TEXCOORD0;    // the point on the near plane this pixel looks along
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(uint VertexID : SV_VertexID)
{
    fs_Input Result;

    const float2 Clip = ZyEmitScreen(VertexID).xy;

    Result.Position = float4(Clip, 0.0, 1.0);
    Result.Probe    = Clip;

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

Texture2D    t_Normal : register(t0);
SamplerState s_Normal : register(s0);

Texture2D    t_Albedo : register(t1);
SamplerState s_Albedo : register(s1);

Texture2D    t_Depth    : register(t2);
SamplerState s_Depth    : register(s2);

Texture2D    t_Sunlight : register(t3);
SamplerState s_Sunlight : register(s3);

float Sunlit(float3 World)
{
    const float4 Lit = mul(u_Sunlight, float4(World, 1.0));
    const float2 Map = Lit.xy * float2(0.5, -0.5) + 0.5;

    if (any(Map < 0.0) || any(Map > 1.0) || Lit.z < 0.0 || Lit.z > 1.0)
    {
        return 1.0;
    }

    const float Depth = Lit.z - kSunBias;

    float Sum = 0.0;

    [unroll]
    for (int Y = -1; Y <= 1; ++Y)
    {
        [unroll]
        for (int X = -1; X <= 1; ++X)
        {
            const float2 Tap = Map + float2(X, Y) * u_Sunstep.xy;

            Sum += (Depth <= t_Sunlight.SampleLevel(s_Sunlight, Tap, 0).r) ? 1.0 : 0.0;
        }
    }
    return Sum * (1.0 / 9.0);
}

float3 main(fs_Input Input) : SV_Target0
{
    const int3   Texel  = int3(Input.Position.xy, 0);
    const float4 Base   = t_Albedo.Load(Texel);
    const float3 Albedo = Base.rgb;
    const float3 Normal = normalize(ZyDecodeNormalMap(t_Normal.Load(Texel).rgb));

    // The same reading the local lights take, so both agree on where a pixel actually stands.
    const float  Sorted = t_Depth.Load(Texel).r;
    const float  Depth  = Sorted - Base.a * kReliefRange / ZyDepthSpan(u_CameraInverse);
    const float4 Probe  = mul(u_CameraInverse, float4(Input.Probe, ZyClipDepth(Depth), 1.0));
    const float3 World  = Probe.xyz / Probe.w;

    // Hemisphere ambient. The weight is world Y, so this reads as "facing the sky" only because the normal
    // buffer stores world-space normals with Y up.
    const float  Weight  = Normal.y * 0.5 + 0.5;
    const float3 Ambient = lerp(u_GroundColor.rgb, u_SkyColor.rgb, Weight);
    const float3 Toward  = float3(u_SunColor.w, u_SkyColor.w, u_GroundColor.w);
    const float3 Sun     = u_SunColor.rgb * saturate(dot(Normal, Toward)) * Sunlit(World);

    // Every light shades the surface it lands on, so the radiance target holds scene color and the composite
    // only tone maps it. Summing the lights and multiplying once at the end is the same math.
    return Albedo * (Ambient + Sun);
}

#endif // FRAGMENT_SHADER