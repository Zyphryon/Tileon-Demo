// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Embedded://Shader/Affine.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    mat4 u_Sunlight;    // Turns world space into the sun's own clip space.
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

layout(location = 0) in vec4 a_Transform0;
layout(location = 1) in vec4 a_Transform1;
layout(location = 2) in vec4 a_Transform2;
layout(location = 3) in vec3 a_Size;       // the ground covered along x and z, and the height reached along y
layout(location = 4) in uint a_Face;       // which face of the box this quad stands for

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
    vec2     Corner    = ZyEmitRect(gl_VertexID);
    ZyAffine Transform = ZyReadAffine(a_Transform0, a_Transform1, a_Transform2);
    vec3     Position  = ZyApplyAffine(Transform, PlaceFace(a_Face, Corner, a_Size));

    // The map is a plain depth buffer, so the distance along the sun is what the rasterizer already keeps.
    gl_Position = u_Sunlight * vec4(Position, 1.0);
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

/// The map keeps the nearest blocker, which the depth test settles on its own.
void main()
{
}

#endif // FRAGMENT_SHADER