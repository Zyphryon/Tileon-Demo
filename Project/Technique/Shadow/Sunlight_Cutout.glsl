// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    mat4 u_Sunlight;    // Turns world space into the sun's own clip space.
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

layout(location = 0) in vec4 a_Origin;    // where the quad rises from, with the cutoff its art is cut at in w
layout(location = 1) in vec4 a_SpanU;     // the run across the quad, with the layer of a layered material in w
layout(location = 2) in vec4 a_SpanV;     // the rise up the quad, with w unused
layout(location = 3) in vec4 a_Frame;     // the art's crop, with any mirroring already turned into the endpoints

out vec2       v_Texture;    // the texel of the art the quad is cut out by
flat out float v_Cutoff;     // the alpha under which a texel is no blocker
#ifdef ENABLE_LAYERED
flat out float v_Layer;      // the layer of the material's array the art is read from
#endif

void main()
{
    vec2 Corner = ZyEmitRect(gl_VertexID);

    gl_Position = u_Sunlight * vec4(a_Origin.xyz + Corner.x * a_SpanU.xyz + Corner.y * a_SpanV.xyz, 1.0);
    v_Texture   = mix(a_Frame.xy, a_Frame.zw, Corner);
    v_Cutoff    = a_Origin.w;
#ifdef ENABLE_LAYERED
    v_Layer     = a_SpanU.w;
#endif
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

#ifdef ENABLE_LAYERED
layout(binding = 0) uniform sampler2DArray t_Albedo;
#else
layout(binding = 0) uniform sampler2D      t_Albedo;
#endif

in vec2       v_Texture;
flat in float v_Cutoff;
#ifdef ENABLE_LAYERED
flat in float v_Layer;
#endif

/// The map keeps the nearest blocker, which the depth test settles once the cutout is carved away.
void main()
{
#ifdef ENABLE_LAYERED
    if (texture(t_Albedo, vec3(v_Texture, v_Layer)).a < v_Cutoff)
#else
    if (texture(t_Albedo, v_Texture).a < v_Cutoff)
#endif
    {
        discard;
    }
}

#endif // FRAGMENT_SHADER