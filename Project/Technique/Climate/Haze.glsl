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
#include "Resources://Technique/Common/Scene.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    vec4 u_Tint;        // the color of the mist as authored, and how much of the scene it hides at its thickest
    vec4 u_Sky;         // the light the sky lends the mist, and how wide one texel of the sun's map is
    vec4 u_Sun;         // the light the sun lends the mist where it reaches it, with the last lane unused
    vec4 u_Mist;        // how high the mist stands, how wide one billow runs, how fast it drifts, and how torn it reads
    vec4 u_Wind;        // the wind across the ground, which the mist is carried on, and how gusty it is
    mat4 u_Sunlight;    // turns world space into the sun's clip space, which its map is read through
};

/// How far a point is let off the sun's map before it is taken to be standing in its own shadow.
const float kSunBias      = 0.0015;

/// How many heights of the layer the ray is followed up before the mist is taken to have thinned to nothing.
const float kReach        = 3.0;

/// How much of the light a layer's worth of mist takes away, which calibrates the density knob against Flat.
const float kExtinction   = 2.0;

/// How much of the sun still reaches mist standing in shadow, bounced in off the lit mist around it.
const float kShadowFloor  = 0.35;

/// How far apart the taps on the sun's map are spread, in texels, which is what softens a shaft's edge.
const float kShadowSpread = 2.0;

/// How much of the wind's speed the mist is carried at, on top of the drift it was given.
const float kWindCarry    = 0.5;

/// How many steps the mist is marched in, when it is marched at all.
const int   kSteps        = 12;

#ifdef VERTEX_SHADER

out vec2 v_Probe;    // the pixel's clip-space coordinates

void main()
{
    vec4 Screen = ZyEmitScreen(gl_VertexID);

    gl_Position = vec4(Screen.xy, 0.0, 1.0);
    v_Probe     = Screen.xy;
}

#endif // VERTEX_SHADER

#ifdef FRAGMENT_SHADER

layout(binding = 0) uniform sampler2D       t_Depth;
layout(binding = 1) uniform sampler2DShadow t_Sunlight;

in vec2 v_Probe;

layout(location = 0) out vec4 out_Color;

/// Reads how thickly the mist billows over one point of the ground, drifting with the clock.
float Field(vec2 Ground, float Time)
{
    // The mist drifts a way of its own, and the wind carries it further along the way it blows.
    vec2 Flow = (vec2(1.0, 0.6) * u_Mist.z + u_Wind.xz * kWindCarry) * Time;

    float Coarse = ZyValueNoise((Ground + Flow) / u_Mist.y);
    float Fine   = ZyValueNoise((Ground - Flow * 0.7) / (u_Mist.y * 0.37) + 17.0);

#if defined(HAZE_LAYERED) || defined(HAZE_VOLUMETRIC)
    // The finer octaves are what turn a blanket into wisps, and are only worth paying for past the cheapest step.
    float Wisp = ZyValueNoise((Ground + Flow * 1.3) / (u_Mist.y * 0.13) + 41.0);

    return Coarse * 0.55 + Fine * 0.3 + Wisp * 0.15;
#else
    return Coarse * 0.65 + Fine * 0.35;
#endif
}

/// Turns the field into cover: torn mist gathers into banks with clear ground between, an even veil covers all.
float Bank(float Field)
{
    return mix(1.0, smoothstep(0.4, 0.75, Field), u_Mist.w);
}

#if defined(HAZE_VOLUMETRIC)

/// Reads how much of the sun reaches a point, off the map the sun laid what it cannot reach into.
float Sunlit(vec4 Lit, vec2 Spin)
{
    vec2 Map = Lit.xy * 0.5 + 0.5;

    if (any(lessThan(Map, vec2(0.0))) || any(greaterThan(Map, vec2(1.0))) || Lit.z < 0.0 || Lit.z > 1.0)
    {
        return 1.0;
    }

    // Four taps a couple of texels out, turned by a different angle per pixel, so the edge of a shadow spreads
    // into a soft rim instead of the map's own texel stair.
    float Depth = (Lit.z - kSunBias) * 0.5 + 0.5;
    vec2  Reach = Spin * (kShadowSpread * u_Sky.w);
    vec2  Cross = vec2(-Reach.y, Reach.x);

    return 0.25 * (textureGrad(t_Sunlight, vec3(Map + Reach, Depth), vec2(0.0), vec2(0.0))
                 + textureGrad(t_Sunlight, vec3(Map - Reach, Depth), vec2(0.0), vec2(0.0))
                 + textureGrad(t_Sunlight, vec3(Map + Cross, Depth), vec2(0.0), vec2(0.0))
                 + textureGrad(t_Sunlight, vec3(Map - Cross, Depth), vec2(0.0), vec2(0.0)));
}

#endif // HAZE_VOLUMETRIC

void main()
{
    ivec2 Texel = ivec2(gl_FragCoord.xy);
    float Depth = texelFetch(t_Depth, Texel, 0).r;

    // Nothing was drawn where the depth was never written, and the mist has no ground there to lie on.
    if (Depth >= 0.99999)
    {
        discard;
    }

    vec4 Probe = u_CameraInverse * vec4(v_Probe, ZyClipDepth(Depth), 1.0);
    vec3 World = Probe.xyz / Probe.w;

    // The field is read against the whole world, so the mist stands still as the frame's origin moves under it.
    vec2  Ground = World.xz + u_Origin.xz;
    float Height = max(World.y, 0.0);
    float Time   = GetSceneTime();
    vec3  Color  = ZyToLinear(u_Tint.rgb);

    // The view is orthographic, so every ray back to the eye climbs out of the layer at the same slant.
    vec3  Toward = normalize((u_CameraInverse * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
    float Climb  = max(-Toward.y, 0.05);

#if defined(HAZE_VOLUMETRIC)

    // The ray is followed from where the pixel landed up to where the mist has thinned to nothing.
    float Top = u_Mist.x * kReach;

    if (Height >= Top)
    {
        discard;
    }

    int   Steps  = kSteps;
    float Span   = (Top - Height) / Climb;
    float Delta  = Span / float(Steps);

    // The sun is asked a little off per pixel, so a shadow's edge blends across the march rather than banding.
    float Noise  = ZyGradientNoise(gl_FragCoord.xy);
    float Jitter = Noise * 0.5;
    vec2  Spin   = vec2(cos(Noise * ZY_TWO_PI), sin(Noise * ZY_TWO_PI));

    // The march walks a straight line and the sun's frame is fixed, so the point it lands on in that frame
    // advances by a constant and the sun is asked where a point stands without projecting it again.
    vec4 Lantern = u_Sunlight * vec4(World, 1.0);
    vec4 Along   = u_Sunlight * vec4(-Toward, 0.0);

    float Through = 1.0;
    vec3  Scatter = vec3(0.0);
    float Prior   = exp(-Height / u_Mist.x);

    for (int Step = 0; Step < Steps; ++Step)
    {
        float Near = float(Step) * Delta;

        // The layer falls off at a fixed rate, so the share of it a segment crosses has a closed form and no
        // step is missed or counted twice; the billows are read once, at the segment's middle.
        float Next   = exp(-(Height + Climb * (Near + Delta)) / u_Mist.x);
        vec3  Middle = World - Toward * (Near + 0.5 * Delta);
        vec2  Under  = Middle.xz + u_Origin.xz + Middle.y * 0.6;
        float Tau    = kExtinction * Bank(Field(Under, Time)) * (Prior - Next) / Climb;
        float Fade   = exp(-Tau);

        Prior = Next;

        // What the sun reaches glows, what it does not is lit by the sky alone: that difference is the shaft.
        float Lit = 0.5 * (Sunlit(Lantern + Along * (Near + Jitter * Delta), Spin)
                         + Sunlit(Lantern + Along * (Near + (0.5 + Jitter) * Delta), Spin));
        vec3 Light = u_Sky.rgb + u_Sun.rgb * mix(kShadowFloor, 1.0, Lit);

        Scatter += Through * (1.0 - Fade) * Light;
        Through *= Fade;
    }

    float Amount = u_Tint.a * (1.0 - Through);

    out_Color = vec4(Color * Scatter * u_Tint.a, Amount);

#else

    float Cover = Bank(Field(Ground, Time)) * exp(-Height / u_Mist.x);

#if defined(HAZE_LAYERED)
    Cover = 1.0 - exp(-kExtinction * Cover / Climb);
#endif

    float Amount = u_Tint.a * Cover;

    out_Color = vec4(Color * (u_Sky.rgb + u_Sun.rgb * 0.5) * Amount, Amount);

#endif
}

#endif // FRAGMENT_SHADER