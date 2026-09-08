// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Embedded://Shader/Packing.hlsl"
#include "Embedded://Shader/Color.hlsl"
#include "Embedded://Shader/Noise.hlsl"
#include "Resources://Technique/Common/Scene.hlsl"

cbuffer cb_Pass : register(b1)
{
    float4 u_Tide;      // the ground plane in view space, the middle step, what a step is worth, and the tide
    float4 u_Shallow;   // the color the water takes where it barely covers the ground
    float4 u_Deep;      // the color the water settles into where it runs deep
    float4 u_Foam;      // the color that gathers where the water thins away to nothing
    float4 u_Surf;      // how far the foam reaches, how broken its edge runs, and how deep it reads as deep
    float4 u_Sheen;     // how brightly the surface catches light, and how fast it works through itself
    float4 u_Wind;      // the wind across the ground, which the swell rolls with, and how gusty it is
};

cbuffer cb_Material : register(b2)
{
    float u_Weave;      // how many world units a whole repeat of the caustic covers
    float u_Speckle;    // how many world units a whole repeat of the scatter covers
};

/// How much of the wind's speed the surface works and the foam is blown at.
static const float kWindWork = 0.08;

/// How much further the foam is torn per unit of wind speed.
static const float kWindTear = 0.02;

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
    float2               World    : TEXCOORD1;
    nointerpolation uint Relief   : TEXCOORD2;
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(vs_Input Input)
{
    fs_Input Result;

    const float2 Corner = ZyEmitRect(Input.VertexID);
    const float2 Unit   = float2(Input.Origin) + Corner * OCEAN_UNITS_PER_REGION;

    // The sheet lies on the ground it floods rather than standing at the tide.
    Result.Position = mul(u_Camera, float4(Unit.x, u_Tide.x, Unit.y, 1.0));
    Result.Ground   = Corner;
    Result.World    = Unit + u_Origin.xz;
    Result.Relief   = Input.Relief;

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

Texture2DArray t_Relief  : register(t0);
SamplerState   s_Relief  : register(s0);
Texture2D      t_Caustic : register(t1);
SamplerState   s_Caustic : register(s1);
Texture2D      t_Noise   : register(t2);
SamplerState   s_Noise   : register(s2);

struct fs_Output
{
    float4 Albedo : SV_Target0;
    float4 Normal : SV_Target1;
};

// A disc gathered as two rings, the outer one turned half a step off the inner so the taps interleave.
static const int    kSurfTaps            = 16;
static const float2 kSurfDisc[kSurfTaps] = {
    float2( 0.55000,  0.00000), float2( 0.38891,  0.38891), float2( 0.00000,  0.55000), float2(-0.38891,  0.38891),
    float2(-0.55000,  0.00000), float2(-0.38891, -0.38891), float2( 0.00000, -0.55000), float2( 0.38891, -0.38891),
    float2( 0.92388,  0.38268), float2( 0.38268,  0.92388), float2(-0.38268,  0.92388), float2(-0.92388,  0.38268),
    float2(-0.92388, -0.38268), float2(-0.38268, -0.92388), float2( 0.38268, -0.92388), float2( 0.92388, -0.38268) };

// Returns how high the ground stands at one point of the page, in world units, taken back out of the step
// the elevation was stored as.
float Stand(float2 Uv, float Page)
{
    return (t_Relief.Sample(s_Relief, float3(Uv, Page)).r * 255.0 - u_Tide.y) * u_Tide.z;
}

// Returns which side of the waterline a point falls on, from all of it drowned at minus one to all of it
// dry at one, gathered over a disc rather than read off the one weight underneath.
float Shore(float2 Uv, float Page, float Reach, float Size)
{
    if (Reach <= 0.0)
    {
        return clamp((Stand(Uv, Page) - u_Tide.w) / 0.25, -1.0, 1.0);
    }

    // Every tap of the disc is filtered, so the line keeps its sub-texel footing however wide the reach
    // is turned, instead of stepping along the ground's own texels.
    float Gathered = 0.0;

    [unroll]
    for (int Tap = 0; Tap < kSurfTaps; ++Tap)
    {
        const float2 Spot = Uv + kSurfDisc[Tap] * (Reach / Size);

        Gathered += clamp((Stand(Spot, Page) - u_Tide.w) / 0.25, -1.0, 1.0);
    }
    return Gathered / float(kSurfTaps);
}

// Returns how much light gathers here, over nought upward. The same net is read twice, at scales that share
// no common multiple and drifting apart, so its repeats never line up; `min` keeps the thin lines thin.
float Caustic(float2 World, float Time)
{
    // The swell rolls the way the wind blows, and the harder it blows the faster the surface works.
    const float  Blow  = length(u_Wind.xz);
    const float2 Along = (Blow > 0.001) ? u_Wind.xz / Blow : float2(0.85, 0.53);
    const float2 Cross = float2(-Along.y, Along.x);
    const float  Pace  = u_Sheen.y + Blow * kWindWork;

    const float2 UvA = World / u_Weave          + Time * Pace * ( 0.053 * Along);
    const float2 UvB = World / (u_Weave * 0.59) + Time * Pace * (-0.026 * Along + 0.030 * Cross);

    return min(t_Caustic.Sample(s_Caustic, UvA).r, t_Caustic.Sample(s_Caustic, UvB).r);
}

fs_Output main(fs_Input Input)
{
    fs_Output Result;

    // A page carries a ring of its neighbours' ground, so the read steps past it to reach this region's own.
    const float  Size    = OCEAN_UNITS_PER_REGION + 2.0 * OCEAN_MAP_BORDER;
    const float2 Sampled = (Input.Ground * OCEAN_UNITS_PER_REGION + OCEAN_MAP_BORDER) / Size;

    // The line is gathered as wide as the page allows, that ring being all it has to go on.
    const float Edge = Shore(Sampled, Input.Relief, OCEAN_MAP_BORDER * u_Sheen.z, Size);

    const float Fringe = fwidth(Edge);
    const float Covers = clamp(0.5 - Edge / max(Fringe, 1e-5), 0.0, 1.0);

    // Ground standing above the tide is dry, and there is nothing to draw over it.
    if (Covers <= 0.0)
    {
        discard;
    }

    // The gathered line may stand a little inside the ground's own, so the depth is held at nought.
    const float Depth = max(u_Tide.w - Stand(Sampled, Input.Relief), 0.0);

    const float  Time = GetSceneTime();

    // Water swallows red long before blue, which is the whole reason the deep reads blue at all.
    const float3 Fade  = 1.0 - exp(-Depth * float3(1.6, 1.0, 0.7) / max(u_Surf.z, 0.001));
    const float  Sunk  = Fade.g;
    float4       Water = float4(lerp(u_Shallow.rgb, u_Deep.rgb, Fade), lerp(u_Shallow.a, u_Deep.a, Sunk));

    // The filaments belong to the water's own surface, so they go down before the surf that runs over them.
    Water.rgb = lerp(Water.rgb, u_Foam.rgb, Caustic(Input.World, Time) * u_Sheen.x * (1.0 - Sunk));

    // The foam is torn by the grain and blown along by the wind, and a hard wind tears it further.
    const float2 Blown = Input.World + u_Wind.xz * (kWindWork * Time);
    const float  Tear  = min(u_Surf.y + length(u_Wind.xz) * kWindTear, 1.0);
    const float  Torn  = max(1.0 - Tear * t_Noise.Sample(s_Noise, Blown / u_Speckle).r, 0.0);

    // The froth runs a share of the gather's own reach, torn by the grain and carried by the swell.
    const float Wash  = saturate(u_Surf.x / OCEAN_MAP_BORDER) * Torn;
    const float Rim   = saturate((Edge + Wash) / max(Wash, 0.001));
    const float Froth = Rim * Rim;

    Water = lerp(Water, u_Foam, Froth);

    Result.Albedo = float4(ZyToLinear(Water.rgb), Water.a * Covers);
    Result.Normal = float4(ZyEncodeNormalMap(float3(0.0, 1.0, 0.0)), Water.a * Covers);

    return Result;
}

#endif // FRAGMENT_SHADER