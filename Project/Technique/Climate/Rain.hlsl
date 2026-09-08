// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Embedded://Shader/Color.hlsl"
#include "Embedded://Shader/Depth.hlsl"
#include "Embedded://Shader/Math.hlsl"
#include "Embedded://Shader/Noise.hlsl"
#include "Embedded://Shader/Packing.hlsl"
#include "Resources://Technique/Common/Scene.hlsl"

cbuffer cb_Pass : register(b1)
{
    float4   u_Tint;     // the color of the rain as authored, and how bright a streak reads at its head
    float4   u_Light;    // the light the sky lends the rain, and how hard the sky is flashing
    float4   u_Fall;     // how much of the sky is raining, how far a streak leans of its own, how fast it falls, how long it is
    float4   u_Wet;      // unused, how many splashes land, unused, unused
    float4   u_Flash;    // the color of the lightning
    float4   u_Wind;     // the wind across the ground, and how gusty it is
};

/// How many sheets of rain fall at different distances, nearest first.
#if defined(RAIN_SPLASHING)
static const int   kSheets        = 3;
#else
static const int   kSheets        = 2;
#endif

/// How wide one column a drop may fall in is, per sheet, in pixels.
static const float kColumn[3]     = { 5.0, 4.0, 3.0 };

/// How much of the authored length, speed and brightness each sheet keeps, the far ones shorter, slower and dimmer.
static const float kSheet[3]      = { 1.0, 0.7, 0.45 };

/// How far a streak leans per unit of wind along the screen, per pixel fallen.
static const float kLean          = 0.06;

/// How far a gust swings the lean either way, at the wind's gustiest.
static const float kGust          = 0.35;

/// How many world units one splash spreads across the ground.
static const float kSplashCell    = 0.5;

/// How far a splash's ring reaches before it fades, in world units.
static const float kSplashReach   = 0.18;

/// How many splashes a second land in one cell at the heaviest rain.
static const float kSplashRate    = 2.5;

/// How many steps the column above a point is walked looking for something standing over it.
static const int   kShelterSteps  = 12;

/// How high the column above a point is walked, in world units, past which nothing is taken to be over it.
static const float kShelterReach  = 6.0;

/// How far the scene may stand in front of a lifted point before it is taken to be over the point, in depth.
static const float kShelterBias   = 0.0005;

/// How squarely a surface must face the sky to hold the rain off what stands under it.
static const float kShelterFacing = 0.5;

/// How much of the flash lands on what faces the sky, against what faces away from it.
static const float kFlashFacing   = 0.6;

/// How much light the rain keeps when the sky lends it none, so a night's storm still reads.
static const float kRainFloor     = 0.2;

struct fs_Input
{
    float4 Position : SV_POSITION;
    float2 Probe    : TEXCOORD0;    // the pixel's clip-space coordinates
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(uint ID : SV_VertexID)
{
    fs_Input Result;

    const float4 Screen = ZyEmitScreen(ID);

    Result.Position = float4(Screen.xy, 0.0, 1.0);
    Result.Probe    = Screen.xy;

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

Texture2D              t_Depth  : register(t0);
SamplerState           s_Depth  : register(s0);
Texture2D              t_Normal : register(t1);
SamplerState           s_Normal : register(s1);

/// Reads how much of the rain falls through the sheets over one pixel, the drops leaning with the wind.
float Streaks(float2 Pixel, float Lean, float Time)
{
    float Total = 0.0;

    [unroll]
    for (int Sheet = 0; Sheet < kSheets; ++Sheet)
    {
        const float Scale  = kSheet[Sheet];
        const float Width  = kColumn[Sheet];
        const float Length = max(u_Fall.w * Scale, 2.0);
        const float Speed  = u_Fall.z * Scale;

        // Each sheet is sheared by the lean and slid sideways, so no two share a column.
        const float2 Sheared = float2(Pixel.x + Pixel.y * Lean + float(Sheet) * 37.0, Pixel.y);
        const float  Column  = floor(Sheared.x / Width);

        // How much of the sky is raining is how many columns carry a drop at all.
        if (ZyHash21(float2(Column, float(Sheet))) > u_Fall.x)
        {
            continue;
        }

        // A drop falls its column at the sheet's speed, spaced from the next by a gap of its own.
        const float Phase  = ZyHash21(float2(Column, float(Sheet) + 11.0));
        const float Period = Length * lerp(4.0, 9.0, Phase);
        const float Along  = Sheared.y + Time * Speed + Phase * Period;
        const float Cell   = frac(Along / Period) * Period;

        // The head of the drop is its lowest point and its brightest, and the tail thins away above it.
        const float Tail   = Cell < Length ? pow(1.0 - Cell / Length, 1.5) : 0.0;
        const float Across = abs(frac(Sheared.x / Width) - 0.5) * Width;
        const float Line   = 1.0 - smoothstep(0.35, 0.85, Across);

        Total += Tail * Line * Scale;
    }
    return Total;
}

#if defined(RAIN_SPLASHING)

/// Reads the ring a drop leaves where it lands on the ground, one landing at a time per patch of it.
float Splashes(float2 Ground, float Time)
{
    const float2 Cell = floor(Ground / kSplashCell);
    const float  Seed = ZyHash21(Cell);

    // Only some patches are splashing at once, and more of them the heavier the rain falls.
    if (Seed > u_Wet.y)
    {
        return 0.0;
    }

    // The ring grows out from a point of its own within the patch, then fades as it reaches its widest.
    const float2 Centre = (Cell + float2(ZyHash21(Cell + 3.0), ZyHash21(Cell + 7.0))) * kSplashCell;
    const float  Life   = frac(Time * kSplashRate * lerp(0.6, 1.4, Seed) + Seed * 7.0);
    const float  Radius = Life * kSplashReach;
    const float  Ring   = 1.0 - smoothstep(0.0, 0.025 + Radius * 0.15, abs(distance(Ground, Centre) - Radius));

    return Ring * (1.0 - Life) * (1.0 - Life);
}

#endif // RAIN_SPLASHING

#if defined(RAIN_SHELTERED)

/// Reads whether open sky stands over a point, or something is holding the rain off it, by walking up the
/// column above it and asking the depth at each step whether the scene stands in front of it.
float Open(float3 World, float Noise)
{
    // The column is walked in world up, which lands on the screen wherever the camera says it does.
    const float3 Lift  = float3(0.0, kShelterReach / float(kShelterSteps), 0.0);
    const float4 Tread = mul(u_Camera, float4(Lift, 0.0));

    float4 Clip = mul(u_Camera, float4(World + Lift * (1.0 - Noise), 1.0));

    [loop]
    for (int Step = 1; Step <= kShelterSteps; ++Step)
    {
        const float2 Map = Clip.xy * float2(0.5, -0.5) + 0.5;

        // Past the top of the screen nothing more can be seen standing over the point.
        if (any(Map < 0.0) || any(Map > 1.0))
        {
            break;
        }

        if (t_Depth.SampleLevel(s_Depth, Map, 0).r < Clip.z - kShelterBias)
        {
            return ZyDecodeNormalMap(t_Normal.SampleLevel(s_Normal, Map, 0).rgb).y > kShelterFacing ? 0.0 : 1.0;
        }
        Clip += Tread;
    }
    return 1.0;
}

#endif // RAIN_SHELTERED

float4 main(fs_Input Input) : SV_Target0
{
    const int3  Texel = int3(Input.Position.xy, 0);
    const float Depth = t_Depth.Load(Texel).r;
    const float Time  = GetSceneTime();

    const float4 Probe  = mul(u_CameraInverse, float4(Input.Probe, ZyClipDepth(Depth), 1.0));
    const float3 World  = Probe.xyz / Probe.w;
    const float3 Normal = normalize(ZyDecodeNormalMap(t_Normal.Load(Texel).rgb));

    // The rain leans with the wind as it crosses the screen, swinging either way as the wind gusts. The
    // pixel's own row runs the other way from the clip axis here, so the fall is turned to match.
    const float  Blown = dot(u_Wind.xyz, normalize(u_ScreenX.xyz));
    const float  Gust  = (ZyValueNoise(float2(Time * 0.35, 3.0)) - 0.5) * 2.0 * u_Wind.w * kGust;
    const float  Lean  = u_Fall.y + Blown * kLean + Gust;
    const float2 Pixel = float2(Input.Position.x, -Input.Position.y);

    // What holds the rain off a point holds the splashes off it too.
    float Sky = 1.0;
#if defined(RAIN_SHELTERED)
    if (Depth < 0.99999)
    {
        // Each pixel starts its walk a little off the others, so a roof's edge dithers rather than steps.
        Sky = Open(World, ZyGradientNoise(Input.Position.xy) * 0.5);
    }
#endif

    float Fallen = Streaks(Pixel, Lean, Time) * Sky;

#if defined(RAIN_SPLASHING)
    // Ground that faces the sky takes the splashes; a wall in the rain does not.
    if (Depth < 0.99999)
    {
        const float  Upward = saturate(Normal.y);
        const float2 Ground = World.xz + u_Origin.xz;

        Fallen += Splashes(Ground, Time) * Upward * Sky * u_Fall.x;
    }
#endif

    // The rain is lit by the sky the way the ground under it is, so a night's rain reads dark, and the
    // lightning lands on everything, most on what faces the sky it comes from.
    const float3 Color  = ZyToLinear(u_Tint.rgb) * max(u_Light.rgb, kRainFloor.xxx);
    const float  Amount = saturate(Fallen) * u_Tint.a;
    const float  Struck = u_Light.w * lerp(1.0 - kFlashFacing, 1.0, saturate(Normal.y));

    // The rain only ever adds light; an alpha here would darken the scene under every streak at night.
    return float4(Color * Amount + ZyToLinear(u_Flash.rgb) * Struck, 0.0);
}

#endif // FRAGMENT_SHADER