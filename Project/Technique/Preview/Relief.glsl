// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Embedded://Shader/Grid.glsl"
#include "Resources://Technique/Common/Scene.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    vec4 u_Terrain;     // the ground plane in view space, the middle step, what a step is worth, and the waterline
    vec4 u_Contour;     // how strongly the shading covers the view, and how far apart the contours run
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

layout(location = 0) in ivec2 a_Origin;    // the region's corner, in units, relative to the frame's origin
layout(location = 1) in uint  a_Relief;    // the page of the elevation array holding how high its ground stands

out vec2 v_Ground;
flat out uint v_Relief;

void main()
{
    vec2 Corner = ZyEmitRect(gl_VertexID);
    vec2 Unit   = vec2(a_Origin) + Corner * RELIEF_UNITS_PER_REGION;

    // The sheet lies flat on the ground it reads, so it lands exactly where the terrain itself was drawn.
    gl_Position = u_Camera * vec4(Unit.x, u_Terrain.x, Unit.y, 1.0);
    v_Ground    = Corner;
    v_Relief    = a_Relief;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

layout(binding = 0) uniform sampler2DArray t_Relief;

in vec2 v_Ground;
flat in uint v_Relief;

layout(location = 0) out vec4 out_Color;

// Returns the color ground reads as, where zero is as low as the world goes and one as high, against a waterline.
vec3 Hypsometry(float Height, float Sea)
{
    const vec3 kAbyss  = vec3(0.04, 0.09, 0.24);
    const vec3 kWater  = vec3(0.16, 0.44, 0.62);
    const vec3 kShore  = vec3(0.86, 0.81, 0.58);
    const vec3 kMeadow = vec3(0.32, 0.52, 0.26);
    const vec3 kRock   = vec3(0.52, 0.44, 0.36);
    const vec3 kSnow   = vec3(0.96, 0.96, 0.94);

    // Ground the water already stands over runs through the sea's own range, so a flood reads at a glance.
    if (Height <= Sea)
    {
        return mix(kAbyss, kWater, clamp(Height / max(Sea, 0.0001), 0.0, 1.0));
    }

    float Land = clamp((Height - Sea) / max(1.0 - Sea, 0.0001), 0.0, 1.0);

    if (Land < 0.10)
    {
        return mix(kShore, kMeadow, Land / 0.10);
    }

    if (Land < 0.55)
    {
        return mix(kMeadow, kRock, (Land - 0.10) / 0.45);
    }
    return mix(kRock, kSnow, (Land - 0.55) / 0.45);
}

void main()
{
    // A page carries a ring of its neighbours' ground, so the read steps past it to reach this region's own.
    float Size    = RELIEF_UNITS_PER_REGION + 2.0 * RELIEF_MAP_BORDER;
    vec2  Sampled = (v_Ground * RELIEF_UNITS_PER_REGION + RELIEF_MAP_BORDER) / Size;

    // The stored byte spans the whole range, so it is the ramp's own coordinate.
    float Stood  = texture(t_Relief, vec3(Sampled, float(v_Relief))).r;
    float Ground = (Stood * 255.0 - u_Terrain.y) * u_Terrain.z;

    vec3 Tint = Hypsometry(Stood, u_Terrain.w);

    // The contours are the lattice of the steps, drawn one pixel wide wherever the ground crosses one.
    float Ridge = ZyGridLine(Ground / max(u_Contour.y, 0.001));

    out_Color = vec4(mix(Tint, vec3(0.0), Ridge * 0.45), u_Contour.x);
}

#endif // FRAGMENT_SHADER