// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Resources://Technique/Common/Affine.glsl"
#include "Resources://Technique/Common/Sprite.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    mat4 u_Sunlight;    // Turns world space into the sun's own clip space.
};

/// How far the way the art is turned is shifted up into the side's packed word.
const uint kSideMirrorShift = 2u;

/// The bits naming which upright side the quad stands for.
const uint kSideMask        = 3u;

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

in vec4 a_Transform0;
in vec4 a_Transform1;
in vec4 a_Transform2;
in vec3 a_Size;       // the ground covered along x and z, and the height reached along y
in uint a_Side;       // which upright side this quad stands for, and how the art is turned
in vec4 a_Frame;      // the art's crop within the sheet it is packed in

out float v_Along;    // how far along the sun the side stands, over the map's own span
out vec2  v_Texture;  // the texel of the art the side is cut out by

vec3 PlaceSide(uint Side, vec2 Corner, vec3 Size)
{
    vec2 Half = vec2(Size.x, Size.z) * 0.5;

    if (Side < 2u)
    {
        return vec3(mix(-Half.x, Half.x, Corner.x), Corner.y * Size.y, (Side == 0u) ? -Half.y : Half.y);
    }

    return vec3((Side == 2u) ? -Half.x : Half.x, Corner.y * Size.y, mix(-Half.y, Half.y, Corner.x));
}

void main()
{
    uint   Side      = a_Side & kSideMask;
    vec2   Corner    = ZyEmitRect(gl_VertexID);
    Affine Transform = ReadAffine(a_Transform0, a_Transform1, a_Transform2);
    vec3   Position  = ApplyAffine(Transform, PlaceSide(Side, Corner, a_Size));

    // The sun's own camera is orthographic, so the clip depth is already the distance along it, over one.
    vec4 Clip = u_Sunlight * vec4(Position, 1.0);

    // The side reads the art straight across its own run, which is what cuts it to the outline it was drawn with.
    vec2 Sample = ReadSample(a_Side >> kSideMirrorShift, Corner);

    gl_Position = Clip;
    v_Along     = Clip.z;
    v_Texture   = mix(a_Frame.xy, a_Frame.zw, Sample);
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

uniform sampler2D t_Albedo;

in float v_Along;
in vec2  v_Texture;

layout(location = 0) out float out_Along;

/// The map keeps the nearest blocker, which the technique's own minimum blend is what settles.
void main()
{
    if (texture(t_Albedo, v_Texture).a < 0.5)
    {
        discard;
    }

    out_Along = clamp(v_Along, 0.0, 1.0);
}

#endif // FRAGMENT_SHADER