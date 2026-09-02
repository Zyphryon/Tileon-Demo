// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Resources://Technique/Common/Affine.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    mat4 u_Sunlight;    // Turns world space into the sun's own clip space.
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

in vec4 a_Transform0;
in vec4 a_Transform1;
in vec4 a_Transform2;
in vec3 a_Size;       // the ground covered along x and z, and the height reached along y
in uint a_Face;       // which face of the box this quad stands for

out float v_Along;    // how far along the sun the face stands, over the map's own span

vec3 PlaceFace(uint Face, vec2 Corner, vec3 Size)
{
    vec2 Half = vec2(Size.x, Size.z) * 0.5;

    if (Face >= 4u)
    {
        return vec3(mix(-Half.x, Half.x, Corner.x), Size.y, mix(-Half.y, Half.y, Corner.y));
    }

    if (Face < 2u)
    {
        return vec3(mix(-Half.x, Half.x, Corner.x), Corner.y * Size.y, (Face == 0u) ? -Half.y : Half.y);
    }

    return vec3((Face == 2u) ? -Half.x : Half.x, Corner.y * Size.y, mix(-Half.y, Half.y, Corner.x));
}

void main()
{
    vec2   Corner    = ZyEmitRect(gl_VertexID);
    Affine Transform = ReadAffine(a_Transform0, a_Transform1, a_Transform2);
    vec3   Position  = ApplyAffine(Transform, PlaceFace(a_Face, Corner, a_Size));

    // The sun's own camera is orthographic, so the clip depth is already the distance along it, over one.
    vec4 Clip = u_Sunlight * vec4(Position, 1.0);

    gl_Position = Clip;
    v_Along     = Clip.z;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

in float v_Along;

layout(location = 0) out float out_Along;

/// The map keeps the nearest blocker, which the technique's own minimum blend is what settles.
void main()
{
    out_Along = clamp(v_Along, 0.0, 1.0);
}

#endif // FRAGMENT_SHADER