// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Resources://Technique/Common/Scene.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    vec2 u_Dimension;
};

const vec4 kColorTiles   = vec4(1.00, 1.00, 1.00, 0.10);
const vec4 kColorRegions = vec4(0.100482, 0.522522, 1.000000, 0.60);

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

out vec2 v_World;

void main()
{
    gl_Position = vec4(ZyEmitScreen(gl_VertexID).xy, 0.0, 1.0);

    vec4 Head = u_CameraInverse * vec4(gl_Position.xy, 0.0, 1.0);
    vec4 Tail = u_CameraInverse * vec4(gl_Position.xy, 1.0, 1.0);

    vec3 Origin    = Head.xyz / Head.w;
    vec3 Direction = Tail.xyz / Tail.w - Origin;

    v_World = (Origin - Direction * (Origin.y / Direction.y)).xz;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

in vec2 v_World;

layout(location = 0) out vec4 out_Color;

// Returns the anti-aliased line coverage of the lattice with the given period, at this fragment.
float Coverage(vec2 World, vec2 Period)
{
    vec2 Repeat   = World / Period;
    vec2 Derivate = max(fwidth(Repeat), vec2(1e-8));
    vec2 Distance = abs(fract(Repeat - 0.5) - 0.5) / Derivate;

    // Once the lines sit closer than a couple of pixels apart they alias into noise, so dissolve them instead.
    float Density = clamp(1.0 - max(Derivate.x, Derivate.y) * 2.0, 0.0, 1.0);
    return clamp(1.0 - min(Distance.x, Distance.y), 0.0, 1.0) * Density;
}

void main()
{
    float Tile   = Coverage(v_World, vec2(1.0));
    float Region = Coverage(v_World, u_Dimension);

    vec4 Result  = mix(
        vec4(kColorTiles.rgb,   kColorTiles.a   * Tile),
        vec4(kColorRegions.rgb, kColorRegions.a * Region), Region);

    if (Result.a < 0.001)
    {
        discard;
    }
    out_Color = Result;
}

#endif // FRAGMENT_SHADER