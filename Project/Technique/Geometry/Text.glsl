// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Embedded://Shader/Font.glsl"
#include "Resources://Technique/Common/Scene.glsl"
#include "Embedded://Shader/Affine.glsl"

layout(std140, binding = 2) uniform cb_Material
{
    vec2 u_Range;
};

struct PackedFontParameters
{
    vec4         u_Transform0;
    vec4         u_Transform1;
    vec4         u_Transform2;
    ZyFontEffect u_Effect;
};

layout(std140, binding = 3) uniform cb_Instance
{
    PackedFontParameters u_Parameters[128];
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

layout(location = 0) in vec4  a_Frame;   // normalized atlas edges: minimum.xy, maximum.xy
layout(location = 1) in ivec2 a_Offset;  // corner within the text layout, in subpixel steps
layout(location = 2) in uvec2 a_Size;    // extent, in subpixel steps
layout(location = 3) in uint  a_Effect;   // the interned effect slot
layout(location = 4) in vec4  a_Color;

out vec4 v_Color;
out vec2 v_Texture;
flat out uint v_Effect;

void main()
{
    vec2 Corner = ZyEmitRect(gl_VertexID);

    PackedFontParameters Run = u_Parameters[a_Effect];

    vec2     Plane     = (vec2(a_Offset) + Corner * vec2(a_Size)) * GLYPH_SUBPIXEL;
    ZyAffine Transform = ZyReadAffine(Run.u_Transform0, Run.u_Transform1, Run.u_Transform2);
    vec3     Position  = ZyApplyAffine(Transform, vec3(Plane, 0.0));

    gl_Position = u_Camera * vec4(Position, 1.0);

    v_Texture = mix(a_Frame.xy, a_Frame.zw, Corner);
    v_Color   = a_Color;
    v_Effect  = a_Effect;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

layout(binding = 0) uniform sampler2D t_Albedo;

in vec4 v_Color;
in vec2 v_Texture;
flat in uint v_Effect;

layout(location = 0) out vec4 out_Color;

void main()
{
    PackedFontParameters Font = u_Parameters[v_Effect];

    vec4  Sample = texture(t_Albedo, v_Texture);
    float Spread = ZyFontSpread(v_Texture, u_Range);

    out_Color = ZyFontShade(Font.u_Effect, Sample, Spread, v_Color);
}

#endif // FRAGMENT_SHADER