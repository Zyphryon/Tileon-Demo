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
#include "Resources://Technique/Common/Scene.hlsl"

cbuffer cb_Pass : register(b1)
{
    float4   u_Tint;        // the color of the mist as authored, and how much of the scene it hides at its thickest
    float4   u_Sky;         // the light the sky lends the mist, and how wide one texel of the sun's map is
    float4   u_Sun;         // the light the sun lends the mist where it reaches it, with the last lane unused
    float4   u_Mist;        // how high the mist stands, how wide one billow runs, how fast it drifts, and how torn it reads
    float4   u_Wind;        // the wind across the ground, which the mist is carried on, and how gusty it is
    float4x4 u_Sunlight;    // turns world space into the sun's clip space, which its map is read through
};

/// How far a point is let off the sun's map before it is taken to be standing in its own shadow.
static const float kSunBias      = 0.0015;

/// How many heights of the layer the ray is followed up before the mist is taken to have thinned to nothing.
static const float kReach        = 3.0;

/// How much of the light a layer's worth of mist takes away, which calibrates the density knob against Flat.
static const float kExtinction   = 2.0;

/// How much of the sun still reaches mist standing in shadow, bounced in off the lit mist around it.
static const float kShadowFloor  = 0.35;

/// How far apart the taps on the sun's map are spread, in texels, which is what softens a shaft's edge.
static const float kShadowSpread = 2.0;

/// How much of the wind's speed the mist is carried at, on top of the drift it was given.
static const float kWindCarry    = 0.5;

/// How many steps the mist is marched in, when it is marched at all.
static const int   kSteps        = 12;

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

Texture2D              t_Depth    : register(t0);
Texture2D              t_Sunlight : register(t1);
SamplerComparisonState s_Sunlight : register(s1);

// Reads how thickly the mist billows over one point of the ground, drifting with the clock.
float Field(float2 Ground, float Time)
{
    // The mist drifts a way of its own, and the wind carries it further along the way it blows.
    const float2 Flow = (float2(1.0, 0.6) * u_Mist.z + u_Wind.xz * kWindCarry) * Time;

    const float Coarse = ZyValueNoise((Ground + Flow) / u_Mist.y);
    const float Fine   = ZyValueNoise((Ground - Flow * 0.7) / (u_Mist.y * 0.37) + 17.0);

#if defined(HAZE_LAYERED) || defined(HAZE_VOLUMETRIC)
    // The finer octaves are what turn a blanket into wisps, and are only worth paying for past the cheapest step.
    const float Wisp = ZyValueNoise((Ground + Flow * 1.3) / (u_Mist.y * 0.13) + 41.0);

    return Coarse * 0.55 + Fine * 0.3 + Wisp * 0.15;
#else
    return Coarse * 0.65 + Fine * 0.35;
#endif
}

// Turns the field into cover: torn mist gathers into banks with clear ground between, an even veil covers all.
float Bank(float Field)
{
    return lerp(1.0, smoothstep(0.4, 0.75, Field), u_Mist.w);
}

#if defined(HAZE_VOLUMETRIC)

// Reads how much of the sun reaches a point, off the map the sun laid what it cannot reach into.
float Sunlit(float4 Lit, float2 Spin)
{
    const float2 Map = Lit.xy * float2(0.5, -0.5) + 0.5;

    if (any(Map < 0.0) || any(Map > 1.0) || Lit.z < 0.0 || Lit.z > 1.0)
    {
        return 1.0;
    }

    // Four taps a couple of texels out, turned by a different angle per pixel, so the edge of a shadow spreads
    // into a soft rim instead of the map's own texel stair.
    const float  Depth = Lit.z - kSunBias;
    const float2 Reach = Spin * (kShadowSpread * u_Sky.w);
    const float2 Cross = float2(-Reach.y, Reach.x);

    return 0.25 * (t_Sunlight.SampleCmpLevelZero(s_Sunlight, Map + Reach, Depth)
                 + t_Sunlight.SampleCmpLevelZero(s_Sunlight, Map - Reach, Depth)
                 + t_Sunlight.SampleCmpLevelZero(s_Sunlight, Map + Cross, Depth)
                 + t_Sunlight.SampleCmpLevelZero(s_Sunlight, Map - Cross, Depth));
}

#endif // HAZE_VOLUMETRIC

float4 main(fs_Input Input) : SV_Target0
{
    const int3  Texel = int3(Input.Position.xy, 0);
    const float Depth = t_Depth.Load(Texel).r;

    // Nothing was drawn where the depth was never written, and the mist has no ground there to lie on.
    if (Depth >= 0.99999)
    {
        discard;
    }

    const float4 Probe = mul(u_CameraInverse, float4(Input.Probe, ZyClipDepth(Depth), 1.0));
    const float3 World = Probe.xyz / Probe.w;

    // The field is read against the whole world, so the mist stands still as the frame's origin moves under it.
    const float2 Ground = World.xz + u_Origin.xz;
    const float  Height = max(World.y, 0.0);
    const float  Time   = GetSceneTime();
    const float3 Color  = ZyToLinear(u_Tint.rgb);

    // The view is orthographic, so every ray back to the eye climbs out of the layer at the same slant.
    const float3 Toward = normalize(mul(u_CameraInverse, float4(0.0, 0.0, 1.0, 0.0)).xyz);
    const float  Climb  = max(-Toward.y, 0.05);

#if defined(HAZE_VOLUMETRIC)

    // The ray is followed from where the pixel landed up to where the mist has thinned to nothing.
    const float Top = u_Mist.x * kReach;

    if (Height >= Top)
    {
        discard;
    }

    const int   Steps = kSteps;
    const float Span  = (Top - Height) / Climb;
    const float Delta = Span / float(Steps);

    // The sun is asked a little off per pixel, so a shadow's edge blends across the march rather than banding.
    const float  Noise  = ZyGradientNoise(Input.Position.xy);
    const float  Jitter = Noise * 0.5;
    const float2 Spin   = float2(cos(Noise * ZY_TWO_PI), sin(Noise * ZY_TWO_PI));

    // The march walks a straight line and the sun's frame is fixed, so the point it lands on in that frame
    // advances by a constant and the sun is asked where a point stands without projecting it again.
    const float4 Lantern = mul(u_Sunlight, float4(World, 1.0));
    const float4 Along   = mul(u_Sunlight, float4(-Toward, 0.0));

    float  Through = 1.0;
    float3 Scatter = float3(0.0, 0.0, 0.0);
    float  Prior   = exp(-Height / u_Mist.x);

    [loop]
    for (int Step = 0; Step < Steps; ++Step)
    {
        const float Near = float(Step) * Delta;

        // The layer falls off at a fixed rate, so the share of it a segment crosses has a closed form and no
        // step is missed or counted twice; the billows are read once, at the segment's middle.
        const float  Next   = exp(-(Height + Climb * (Near + Delta)) / u_Mist.x);
        const float3 Middle = World - Toward * (Near + 0.5 * Delta);
        const float2 Under  = Middle.xz + u_Origin.xz + Middle.y * 0.6;
        const float  Tau    = kExtinction * Bank(Field(Under, Time)) * (Prior - Next) / Climb;
        const float  Fade   = exp(-Tau);

        Prior = Next;

        // What the sun reaches glows, what it does not is lit by the sky alone: that difference is the shaft.
        const float Lit = 0.5 * (Sunlit(Lantern + Along * (Near + Jitter * Delta), Spin)
                               + Sunlit(Lantern + Along * (Near + (0.5 + Jitter) * Delta), Spin));
        const float3 Light = u_Sky.rgb + u_Sun.rgb * lerp(kShadowFloor, 1.0, Lit);

        Scatter += Through * (1.0 - Fade) * Light;
        Through *= Fade;
    }

    const float Amount = u_Tint.a * (1.0 - Through);

    return float4(Color * Scatter * u_Tint.a, Amount);

#else

    float Cover = Bank(Field(Ground, Time)) * exp(-Height / u_Mist.x);

#if defined(HAZE_LAYERED)
    Cover = 1.0 - exp(-kExtinction * Cover / Climb);
#endif

    const float Amount = u_Tint.a * Cover;

    return float4(Color * (u_Sky.rgb + u_Sun.rgb * 0.5) * Amount, Amount);

#endif
}

#endif // FRAGMENT_SHADER