// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Embedded://Shader/Packing.glsl"
#include "Embedded://Shader/Color.glsl"
#include "Embedded://Shader/Noise.glsl"
#include "Resources://Technique/Common/Scene.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    vec4 u_Tide;        // the ground plane in view space, the middle step, what a step is worth, and the tide
    vec4 u_Shallow;     // the color the water takes where it barely covers the ground
    vec4 u_Deep;        // the color the water settles into where it runs deep
    vec4 u_Foam;        // the color that gathers where the water thins away to nothing
    vec4 u_Surf;        // how far the foam reaches, how broken its edge runs, and how deep it reads as deep
    vec4 u_Sheen;       // how brightly the surface catches light, and how fast it works through itself
    vec4 u_Wind;        // the wind across the ground, which the swell rolls with, and how gusty it is
};

layout(std140, binding = 2) uniform cb_Material
{
    float u_Weave;      // how many world units a whole repeat of the caustic covers
    float u_Speckle;    // how many world units a whole repeat of the scatter covers
};

/// How much of the wind's speed the surface works and the foam is blown at.
const float kWindWork = 0.08;

/// How much further the foam is torn per unit of wind speed.
const float kWindTear = 0.02;

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

layout(location = 0) in ivec2 a_Origin;    // the region's corner, in units, relative to the frame's origin
layout(location = 1) in uint  a_Relief;    // the page of the elevation array holding how high its ground stands

out vec2 v_Ground;
out vec2 v_World;
flat out uint v_Relief;


void main()
{
    vec2 Corner = ZyEmitRect(gl_VertexID);
    vec2 Unit   = vec2(a_Origin) + Corner * OCEAN_UNITS_PER_REGION;

    // The sheet lies on the ground it floods rather than standing at the tide.
    gl_Position = u_Camera * vec4(Unit.x, u_Tide.x, Unit.y, 1.0);
    v_Ground    = Corner;
    v_World     = Unit + u_Origin.xz;
    v_Relief    = a_Relief;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

layout(binding = 0) uniform sampler2DArray t_Relief;
layout(binding = 1) uniform sampler2D      t_Caustic;
layout(binding = 2) uniform sampler2D      t_Noise;

in vec2 v_Ground;
in vec2 v_World;
flat in uint v_Relief;

layout(location = 0) out vec4 out_Albedo;
layout(location = 1) out vec4 out_Normal;

// A disc gathered as two rings, the outer one turned half a step off the inner so the taps interleave.
const int  kSurfTaps            = 16;
const vec2 kSurfDisc[kSurfTaps] = vec2[kSurfTaps](
    vec2( 0.55000,  0.00000), vec2( 0.38891,  0.38891), vec2( 0.00000,  0.55000), vec2(-0.38891,  0.38891),
    vec2(-0.55000,  0.00000), vec2(-0.38891, -0.38891), vec2( 0.00000, -0.55000), vec2( 0.38891, -0.38891),
    vec2( 0.92388,  0.38268), vec2( 0.38268,  0.92388), vec2(-0.38268,  0.92388), vec2(-0.92388,  0.38268),
    vec2(-0.92388, -0.38268), vec2(-0.38268, -0.92388), vec2( 0.38268, -0.92388), vec2( 0.92388, -0.38268));

// Returns how high the ground stands at one point of the page, in world units, taken back out of the step
// the elevation was stored as.
float Stand(vec2 Uv, float Page)
{
    return (texture(t_Relief, vec3(Uv, Page)).r * 255.0 - u_Tide.y) * u_Tide.z;
}

// Returns which side of the waterline a point falls on, from all of it drowned at minus one to all of it
// dry at one, gathered over a disc rather than read off the one weight underneath.
float Shore(vec2 Uv, float Page, float Reach, float Size)
{
    if (Reach <= 0.0)
    {
        return clamp((Stand(Uv, Page) - u_Tide.w) / 0.25, -1.0, 1.0);
    }

    // Every tap of the disc is filtered, so the line keeps its sub-texel footing however wide the reach
    // is turned, instead of stepping along the ground's own texels.
    float Gathered = 0.0;

    for (int Tap = 0; Tap < kSurfTaps; ++Tap)
    {
        vec2 Spot = Uv + kSurfDisc[Tap] * (Reach / Size);

        Gathered += clamp((Stand(Spot, Page) - u_Tide.w) / 0.25, -1.0, 1.0);
    }
    return Gathered / float(kSurfTaps);
}

// Returns how much light gathers here, over nought upward. The same net is read twice, at scales that share
// no common multiple and drifting apart, so its repeats never line up; `min` keeps the thin lines thin.
float Caustic(vec2 World, float Time)
{
    // The swell rolls the way the wind blows, and the harder it blows the faster the surface works.
    float Blow  = length(u_Wind.xz);
    vec2  Along = (Blow > 0.001) ? u_Wind.xz / Blow : vec2(0.85, 0.53);
    vec2  Cross = vec2(-Along.y, Along.x);
    float Pace  = u_Sheen.y + Blow * kWindWork;

    vec2 UvA = World / u_Weave          + Time * Pace * ( 0.053 * Along);
    vec2 UvB = World / (u_Weave * 0.59) + Time * Pace * (-0.026 * Along + 0.030 * Cross);

    return min(texture(t_Caustic, UvA).r, texture(t_Caustic, UvB).r);
}

void main()
{
    // A page carries a ring of its neighbours' ground, so the read steps past it to reach this region's own.
    float Size    = OCEAN_UNITS_PER_REGION + 2.0 * OCEAN_MAP_BORDER;
    vec2  Sampled = (v_Ground * OCEAN_UNITS_PER_REGION + OCEAN_MAP_BORDER) / Size;

    // The line is gathered as wide as the page allows, that ring being all it has to go on.
    float Edge = Shore(Sampled, float(v_Relief), OCEAN_MAP_BORDER * u_Sheen.z, Size);

    float Fringe = fwidth(Edge);
    float Covers = clamp(0.5 - Edge / max(Fringe, 1e-5), 0.0, 1.0);

    // Ground standing above the tide is dry, and there is nothing to draw over it.
    if (Covers <= 0.0)
    {
        discard;
    }

    // The gathered line may stand a little inside the ground's own, so the depth is held at nought.
    float Depth = max(u_Tide.w - Stand(Sampled, float(v_Relief)), 0.0);

    float Time = GetSceneTime();

    // Water swallows red long before blue, which is the whole reason the deep reads blue at all.
    vec3  Fade  = 1.0 - exp(-Depth * vec3(1.6, 1.0, 0.7) / max(u_Surf.z, 0.001));
    float Sunk  = Fade.g;
    vec4  Water = vec4(mix(u_Shallow.rgb, u_Deep.rgb, Fade), mix(u_Shallow.a, u_Deep.a, Sunk));

    // The filaments belong to the water's own surface, so they go down before the surf that runs over them.
    Water.rgb = mix(Water.rgb, u_Foam.rgb, Caustic(v_World, Time) * u_Sheen.x * (1.0 - Sunk));

    // What laps at the shore is the same swell that is rolling across the water, so the two agree.
    // The foam is torn by the grain and blown along by the wind, and a hard wind tears it further.
    vec2  Blown = v_World + u_Wind.xz * (kWindWork * Time);
    float Tear  = min(u_Surf.y + length(u_Wind.xz) * kWindTear, 1.0);
    float Torn  = max(1.0 - Tear * texture(t_Noise, Blown / u_Speckle).r, 0.0);

    // The froth runs a share of the gather's own reach, torn by the grain and carried by the swell.
    float Wash  = clamp(u_Surf.x / OCEAN_MAP_BORDER, 0.0, 1.0) * Torn;
    float Rim   = clamp((Edge + Wash) / max(Wash, 0.001), 0.0, 1.0);
    float Froth = Rim * Rim;

    Water = mix(Water, u_Foam, Froth);

    out_Albedo = vec4(ZyToLinear(Water.rgb), Water.a * Covers);
    out_Normal = vec4(ZyEncodeNormalMap(vec3(0.0, 1.0, 0.0)), Water.a * Covers);
}

#endif // FRAGMENT_SHADER