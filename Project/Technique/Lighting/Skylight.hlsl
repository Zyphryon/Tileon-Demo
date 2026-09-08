// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
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

/// How far a point is lifted off its surface along its normal before the map is asked, in world units, so
/// a face the map itself recorded does not shade the pixels lying on it.
static const float kSunLift = 0.25;

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

Texture2D    		   t_Normal   : register(t0);
SamplerState 		   s_Normal   : register(s0);

Texture2D    		   t_Albedo   : register(t1);
SamplerState 		   s_Albedo   : register(s1);

Texture2D    		   t_Depth    : register(t2);
SamplerState 		   s_Depth    : register(s2);

Texture2D              t_Sunlight : register(t3);
SamplerComparisonState s_Sunlight : register(s3);

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

            // Each tap is a hardware comparison, filtered over its own four texels for free.
            Sum += t_Sunlight.SampleCmpLevelZero(s_Sunlight, Tap, Depth);
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

    // Hemisphere ambient, weighed by world Y, which reads as the sky only because the normals are world.
    const float  Weight  = Normal.y * 0.5 + 0.5;
    const float3 Ambient = lerp(u_GroundColor.rgb, u_SkyColor.rgb, Weight);
    const float3 Toward  = float3(u_SunColor.w, u_SkyColor.w, u_GroundColor.w);
    const float  Facing  = dot(Normal, Toward);

    float3 Sun = float3(0.0, 0.0, 0.0);

    // A surface turned from the sun is dark without asking the map, which spares the whole gather.
    [branch]
    if (Facing > 0.0)
    {
        const float  Sorted = t_Depth.Load(Texel).r;
        const float  Depth  = Sorted - Base.a * kReliefRange * u_ScreenX.w;
        const float4 Probe  = mul(u_CameraInverse, float4(Input.Probe, ZyClipDepth(Depth), 1.0));

        Sun = u_SunColor.rgb * (Facing * Sunlit(Probe.xyz / Probe.w + Normal * kSunLift));
    }

    // Every light shades what it lands on, so the target holds scene color and the composite only tone maps.
    return Albedo * (Ambient + Sun);
}

#endif // FRAGMENT_SHADER