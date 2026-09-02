// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Embedded://Shader/Packing.glsl"
#include "Embedded://Shader/Noise.glsl"
#include "Resources://Technique/Common/Scene.glsl"

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

layout(location = 0) in ivec2 a_Origin;    // region corner, in tiles, relative to the frame's origin
layout(location = 1) in uint  a_Weights;   // slice of the weight array, and above it how many slots it blends
layout(location = 2) in uvec4 a_Palette;   // slice of the terrain array each of the four slots draws
layout(location = 3) in vec4  a_Mapping;   // how often each slot repeats across one world unit
layout(location = 4) in vec4  a_Phase0;    // where slots 0 and 1 already stand in their repeat, at the region's corner
layout(location = 5) in vec4  a_Phase1;    // the same, for slots 2 and 3
layout(location = 6) in uvec4 a_Tint;      // the color each slot's art is multiplied by, packed as RGBA8
layout(location = 7) in vec4  a_Feather;   // how wide a band each slot's relief feathers over

out vec2 v_Ground;
flat out uint  v_Weights;
flat out uint  v_Count;
flat out uvec4 v_Palette;
flat out vec4  v_Mapping;
flat out vec4  v_Phase[2];
flat out vec4  v_Tint[4];
flat out vec4  v_Feather;

void main()
{
    vec2 Corner = ZyEmitRect(gl_VertexID);
    vec2 Tile   = vec2(a_Origin) + Corner * SPLAT_UNITS_PER_REGION;

    gl_Position = u_Camera * vec4(Tile.x, 0.0, Tile.y, 1.0);

    v_Ground   = Corner;
    v_Weights  = a_Weights & 0xFFFFu;
    v_Count    = a_Weights >> 16;
    v_Palette  = a_Palette;
    v_Mapping  = a_Mapping * SPLAT_UNITS_PER_REGION;
    v_Phase[0] = a_Phase0;
    v_Phase[1] = a_Phase1;
    v_Tint[0]  = ZyUnpackTint(a_Tint.x);
    v_Tint[1]  = ZyUnpackTint(a_Tint.y);
    v_Tint[2]  = ZyUnpackTint(a_Tint.z);
    v_Tint[3]  = ZyUnpackTint(a_Tint.w);

    v_Feather  = a_Feather;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

uniform sampler2DArray t_Weight;
uniform sampler2DArray t_Albedo;
#ifdef ENABLE_NORMAL_MAPPING
uniform sampler2DArray t_Normal;
#endif

in vec2 v_Ground;
flat in uint  v_Weights;
flat in uint  v_Count;
flat in uvec4 v_Palette;
flat in vec4  v_Mapping;
flat in vec4  v_Phase[2];
flat in vec4  v_Tint[4];
flat in vec4  v_Feather;

layout(location = 0) out vec4 out_Albedo;
layout(location = 1) out vec4 out_Normal;

void main()
{
    float Size    = SPLAT_UNITS_PER_REGION + 2.0 * SPLAT_MAP_BORDER;
    vec2  Sampled = (v_Ground * SPLAT_UNITS_PER_REGION + SPLAT_MAP_BORDER) / Size;

    vec4 Weight = texture(t_Weight, vec3(Sampled, float(v_Weights)));

    if (dot(Weight, vec4(1.0)) < SPLAT_WEIGHT_FLOOR)
    {
        discard;
    }

    Weight /= max(dot(Weight, vec4(1.0)), 0.0001);

    vec2 Texture[4];
    vec4 Source[4];
#ifdef ENABLE_HEIGHT_BLEND
    vec4 Height = vec4(0.0);
#endif
#ifdef ENABLE_NORMAL_MAPPING
    vec3 Tangent[4];
#endif

    // Every fetch the pixel takes is issued here, ahead of all the math, so one hides the latency of the next.
    for (int Slot = 0; Slot < 4; ++Slot)
    {
        if (Slot >= int(v_Count)) { continue; }

        vec2 Sweep = (Slot & 1) == 0 ? v_Phase[Slot >> 1].xy : v_Phase[Slot >> 1].zw;

        Texture[Slot] = Sweep + v_Ground * v_Mapping[Slot];
        Source[Slot]  = texture(t_Albedo, vec3(Texture[Slot], float(v_Palette[Slot])));

#ifdef ENABLE_HEIGHT_BLEND
        Height[Slot] = Source[Slot].a
            + (ZyValueNoise(Texture[Slot] * SPLAT_RELIEF_SCALE) - 0.5) * SPLAT_RELIEF_STRENGTH;
#endif

#ifdef ENABLE_NORMAL_MAPPING
        Tangent[Slot] = ZyDecodeNormalMap(texture(t_Normal, vec3(Texture[Slot], float(v_Palette[Slot]))).xyz);
#endif
    }

#ifdef ENABLE_HEIGHT_BLEND
    float Band = max(dot(v_Feather, Weight), 0.001);

    vec4 Raised = (Height + Weight) * step(vec4(SPLAT_WEIGHT_FLOOR), Weight);

    Weight  = max(Raised - (max(max(Raised.x, Raised.y), max(Raised.z, Raised.w)) - Band), vec4(0.0));
    Weight /= max(dot(Weight, vec4(1.0)), 0.0001);
#endif

    vec3 Albedo = vec3(0.0);
    vec2 Slope  = vec2(0.0);

    for (int Slot = 0; Slot < 4; ++Slot)
    {
        if (Slot >= int(v_Count)) { continue; }

        Albedo += Source[Slot].rgb * v_Tint[Slot].rgb * Weight[Slot];

#ifdef ENABLE_NORMAL_MAPPING
        // Averaging unit normals pulls a meeting toward flat, so the slopes each one stands at are mixed.
        Slope += Tangent[Slot].xy * ((1.0 / max(Tangent[Slot].z, 0.0001)) * Weight[Slot]);
#endif
    }

    // TEMPORARY PROBE: each distinct palette slice hashes to its own colour.
    float Probe = float(v_Palette[0]);
    out_Albedo  = vec4(fract(Probe * 0.6180), fract(Probe * 0.3183), fract(Probe * 0.1290), 0.0);

#ifdef ENABLE_NORMAL_MAPPING
    // The ground faces up, so the slope runs along the plane and world up stands at one.
    vec3 Surface = normalize(vec3(Slope.x, 1.0, Slope.y));
    out_Normal = vec4(ZyEncodeNormalMap(Surface), 1.0);
#else
    out_Normal = vec4(ZyEncodeNormalMap(vec3(0.0, 1.0, 0.0)), 1.0);
#endif
}

#endif // FRAGMENT_SHADER