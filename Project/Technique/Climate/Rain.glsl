// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Embedded://Shader/Color.glsl"
#include "Embedded://Shader/Depth.glsl"
#include "Embedded://Shader/Math.glsl"
#include "Embedded://Shader/Noise.glsl"
#include "Embedded://Shader/Packing.glsl"
#include "Resources://Technique/Common/Scene.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    vec4 u_Tint;     // the color of the rain as authored, and how bright a streak reads at its head
    vec4 u_Light;    // the light the sky lends the rain, and how hard the sky is flashing
    vec4 u_Fall;     // how much of the sky is raining, how far a streak leans of its own, how fast it falls, how long it is
    vec4 u_Wet;      // unused, how many splashes land, unused, unused
    vec4 u_Flash;    // the color of the lightning
    vec4 u_Wind;     // the wind across the ground, and how gusty it is
};

/// How many sheets of rain fall at different distances, nearest first.
#if defined(RAIN_SPLASHING)
const int   kSheets       = 3;
#else
const int   kSheets       = 2;
#endif

/// How wide one column a drop may fall in is, per sheet, in pixels.
const float kColumn[3]     = float[3](5.0, 4.0, 3.0);

/// How much of the authored length, speed and brightness each sheet keeps, the far ones shorter, slower and dimmer.
const float kSheet[3]      = float[3](1.0, 0.7, 0.45);

/// How far a streak leans per unit of wind along the screen, per pixel fallen.
const float kLean          = 0.06;

/// How far a gust swings the lean either way, at the wind's gustiest.
const float kGust          = 0.35;

/// How many world units one splash spreads across the ground.
const float kSplashCell    = 0.5;

/// How far a splash's ring reaches before it fades, in world units.
const float kSplashReach   = 0.18;

/// How many splashes a second land in one cell at the heaviest rain.
const float kSplashRate    = 2.5;

/// How many steps the column above a point is walked looking for something standing over it.
const int   kShelterSteps  = 12;

/// How high the column above a point is walked, in world units, past which nothing is taken to be over it.
const float kShelterReach  = 6.0;

/// How far the scene may stand in front of a lifted point before it is taken to be over the point, in depth.
const float kShelterBias   = 0.0005;

/// How squarely a surface must face the sky to hold the rain off what stands under it.
const float kShelterFacing = 0.5;

/// How much of the flash lands on what faces the sky, against what faces away from it.
const float kFlashFacing   = 0.6;

/// How much light the rain keeps when the sky lends it none, so a night's storm still reads.
const float kRainFloor     = 0.2;

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

out vec2 v_Probe;    // the pixel's clip-space coordinates

void main()
{
    vec4 Screen = ZyEmitScreen(gl_VertexID);

    gl_Position = vec4(Screen.xy, 0.0, 1.0);
    v_Probe     = Screen.xy;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

layout(binding = 0) uniform sampler2D       t_Depth;
layout(binding = 1) uniform sampler2D       t_Normal;

in vec2 v_Probe;

layout(location = 0) out vec4 out_Color;

/// Reads how much of the rain falls through the sheets over one pixel, the drops leaning with the wind.
float Streaks(vec2 Pixel, float Lean, float Time)
{
    float Total = 0.0;

    for (int Sheet = 0; Sheet < kSheets; ++Sheet)
    {
        float Scale  = kSheet[Sheet];
        float Width  = kColumn[Sheet];
        float Length = max(u_Fall.w * Scale, 2.0);
        float Speed  = u_Fall.z * Scale;

        // Each sheet is sheared by the lean and slid sideways, so no two share a column.
        vec2  Sheared = vec2(Pixel.x + Pixel.y * Lean + float(Sheet) * 37.0, Pixel.y);
        float Column  = floor(Sheared.x / Width);

        // How much of the sky is raining is how many columns carry a drop at all.
        if (ZyHash21(vec2(Column, float(Sheet))) > u_Fall.x)
        {
            continue;
        }

        // A drop falls its column at the sheet's speed, spaced from the next by a gap of its own.
        float Phase  = ZyHash21(vec2(Column, float(Sheet) + 11.0));
        float Period = Length * mix(4.0, 9.0, Phase);
        float Along  = Sheared.y + Time * Speed + Phase * Period;
        float Cell   = fract(Along / Period) * Period;

        // The head of the drop is its lowest point and its brightest, and the tail thins away above it.
        float Tail   = Cell < Length ? pow(1.0 - Cell / Length, 1.5) : 0.0;
        float Across = abs(fract(Sheared.x / Width) - 0.5) * Width;
        float Line   = 1.0 - smoothstep(0.35, 0.85, Across);

        Total += Tail * Line * Scale;
    }
    return Total;
}

#if defined(RAIN_SPLASHING)

/// Reads the ring a drop leaves where it lands on the ground, one landing at a time per patch of it.
float Splashes(vec2 Ground, float Time)
{
    vec2  Cell   = floor(Ground / kSplashCell);
    float Seed   = ZyHash21(Cell);

    // Only some patches are splashing at once, and more of them the heavier the rain falls.
    if (Seed > u_Wet.y)
    {
        return 0.0;
    }

    // The ring grows out from a point of its own within the patch, then fades as it reaches its widest.
    vec2  Centre = (Cell + vec2(ZyHash21(Cell + 3.0), ZyHash21(Cell + 7.0))) * kSplashCell;
    float Life   = fract(Time * kSplashRate * mix(0.6, 1.4, Seed) + Seed * 7.0);
    float Radius = Life * kSplashReach;
    float Ring   = 1.0 - smoothstep(0.0, 0.025 + Radius * 0.15, abs(distance(Ground, Centre) - Radius));

    return Ring * (1.0 - Life) * (1.0 - Life);
}

#endif // RAIN_SPLASHING

#if defined(RAIN_SHELTERED)

/// Reads whether open sky stands over a point, or something is holding the rain off it, by walking up the
/// column above it and asking the depth at each step whether the scene stands in front of it.
float Open(vec3 World, float Noise)
{
    // The column is walked in world up, which lands on the screen wherever the camera says it does.
    vec3 Lift  = vec3(0.0, kShelterReach / float(kShelterSteps), 0.0);
    vec4 Clip  = u_Camera * vec4(World + Lift * (1.0 - Noise), 1.0);
    vec4 Tread = u_Camera * vec4(Lift, 0.0);

    for (int Step = 1; Step <= kShelterSteps; ++Step)
    {
        vec2 Map = Clip.xy * 0.5 + 0.5;

        // Past the top of the screen nothing more can be seen standing over the point.
        if (any(lessThan(Map, vec2(0.0))) || any(greaterThan(Map, vec2(1.0))))
        {
            break;
        }

        if (texture(t_Depth, Map).r < Clip.z * 0.5 + 0.5 - kShelterBias)
        {
            return ZyDecodeNormalMap(texture(t_Normal, Map).rgb).y > kShelterFacing ? 0.0 : 1.0;
        }
        Clip += Tread;
    }
    return 1.0;
}

#endif // RAIN_SHELTERED

void main()
{
    ivec2 Texel = ivec2(gl_FragCoord.xy);
    float Depth = texelFetch(t_Depth, Texel, 0).r;
    float Time  = GetSceneTime();

    vec4  Probe  = u_CameraInverse * vec4(v_Probe, ZyClipDepth(Depth), 1.0);
    vec3  World  = Probe.xyz / Probe.w;
    vec3  Normal = normalize(ZyDecodeNormalMap(texelFetch(t_Normal, Texel, 0).rgb));

    // The rain leans with the wind as it crosses the screen, swinging either way as the wind gusts.
    float Blown = dot(u_Wind.xyz, normalize(u_ScreenX.xyz));
    float Gust  = (ZyValueNoise(vec2(Time * 0.35, 3.0)) - 0.5) * 2.0 * u_Wind.w * kGust;
    float Lean  = u_Fall.y + Blown * kLean + Gust;

    // What holds the rain off a point holds the splashes off it too.
    float Sky = 1.0;
#if defined(RAIN_SHELTERED)
    if (Depth < 0.99999)
    {
        // Each pixel starts its walk a little off the others, so a roof's edge dithers rather than steps.
        Sky = Open(World, ZyGradientNoise(gl_FragCoord.xy) * 0.5);
    }
#endif

    float Fallen = Streaks(gl_FragCoord.xy, Lean, Time) * Sky;

#if defined(RAIN_SPLASHING)
    // Ground that faces the sky takes the splashes; a wall in the rain does not.
    if (Depth < 0.99999)
    {
        float Upward = clamp(Normal.y, 0.0, 1.0);
        vec2  Ground = World.xz + u_Origin.xz;

        Fallen += Splashes(Ground, Time) * Upward * Sky * u_Fall.x;
    }
#endif

    // The rain is lit by the sky the way the ground under it is, so a night's rain reads dark, and the
    // lightning lands on everything, most on what faces the sky it comes from.
    vec3  Color  = ZyToLinear(u_Tint.rgb) * max(u_Light.rgb, vec3(kRainFloor));
    float Amount = clamp(Fallen, 0.0, 1.0) * u_Tint.a;
    float Struck = u_Light.w * mix(1.0 - kFlashFacing, 1.0, clamp(Normal.y, 0.0, 1.0));

    // The rain only ever adds light; an alpha here would darken the scene under every streak at night.
    out_Color = vec4(Color * Amount + ZyToLinear(u_Flash.rgb) * Struck, 0.0);
}

#endif // FRAGMENT_SHADER