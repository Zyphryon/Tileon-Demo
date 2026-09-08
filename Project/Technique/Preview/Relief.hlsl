// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Embedded://Shader/Grid.hlsl"
#include "Resources://Technique/Common/Scene.hlsl"

cbuffer cb_Pass : register(b1)
{
    float4 u_Terrain;   // the ground plane in view space, the middle step, what a step is worth, and the waterline
    float4 u_Contour;   // how strongly the shading covers the view, and how far apart the contours run
};

struct vs_Input
{
    uint  VertexID : SV_VertexID;

    int2  Origin   : SLOT0;    // the region's corner, in units, relative to the frame's origin
    uint  Relief   : SLOT1;    // the page of the elevation array holding how high this region's ground stands
};

struct fs_Input
{
    float4               Position : SV_POSITION;
    float2               Ground   : TEXCOORD0;
    nointerpolation uint Relief   : TEXCOORD1;
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(vs_Input Input)
{
    fs_Input Result;

    const float2 Corner = ZyEmitRect(Input.VertexID);
    const float2 Unit   = float2(Input.Origin) + Corner * RELIEF_UNITS_PER_REGION;

    // The sheet lies flat on the ground it reads, so it lands exactly where the terrain itself was drawn.
    Result.Position = mul(u_Camera, float4(Unit.x, u_Terrain.x, Unit.y, 1.0));
    Result.Ground   = Corner;
    Result.Relief   = Input.Relief;

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

Texture2DArray t_Relief : register(t0);
SamplerState   s_Relief : register(s0);

// Returns the color ground reads as, where zero is as low as the world goes and one as high, against a waterline.
float3 Hypsometry(float Height, float Sea)
{
    const float3 kAbyss  = float3(0.04, 0.09, 0.24);
    const float3 kWater  = float3(0.16, 0.44, 0.62);
    const float3 kShore  = float3(0.86, 0.81, 0.58);
    const float3 kMeadow = float3(0.32, 0.52, 0.26);
    const float3 kRock   = float3(0.52, 0.44, 0.36);
    const float3 kSnow   = float3(0.96, 0.96, 0.94);

    // Ground the water already stands over runs through the sea's own range, so a flood reads at a glance.
    if (Height <= Sea)
    {
        return lerp(kAbyss, kWater, saturate(Height / max(Sea, 0.0001)));
    }

    const float Land = saturate((Height - Sea) / max(1.0 - Sea, 0.0001));

    if (Land < 0.10)
    {
        return lerp(kShore, kMeadow, Land / 0.10);
    }

    if (Land < 0.55)
    {
        return lerp(kMeadow, kRock, (Land - 0.10) / 0.45);
    }
    return lerp(kRock, kSnow, (Land - 0.55) / 0.45);
}

float4 main(fs_Input Input) : SV_Target0
{
    // A page carries a ring of its neighbours' ground, so the read steps past it to reach this region's own.
    const float  Size    = RELIEF_UNITS_PER_REGION + 2.0 * RELIEF_MAP_BORDER;
    const float2 Sampled = (Input.Ground * RELIEF_UNITS_PER_REGION + RELIEF_MAP_BORDER) / Size;

    // The stored byte spans the whole range, so it is the ramp's own coordinate.
    const float Stood  = t_Relief.Sample(s_Relief, float3(Sampled, Input.Relief)).r;
    const float Ground = (Stood * 255.0 - u_Terrain.y) * u_Terrain.z;

    const float3 Tint = Hypsometry(Stood, u_Terrain.w);

    // The contours are the lattice of the steps, drawn one pixel wide wherever the ground crosses one.
    const float Ridge = ZyGridLine(Ground / max(u_Contour.y, 0.001));

    return float4(lerp(Tint, float3(0.0, 0.0, 0.0), Ridge * 0.45), u_Contour.x);
}

#endif // FRAGMENT_SHADER