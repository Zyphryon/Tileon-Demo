// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Embedded://Shader/Packing.glsl"
#include "Resources://Technique/Common/Scene.glsl"
#include "Resources://Technique/Common/Affine.glsl"

layout(std140, binding = 2) uniform cb_Material
{
    vec2 u_Range;
};

struct PackedFontParameters
{
    vec4  u_Transform0;
    vec4  u_Transform1;
    vec4  u_Transform2;

    uint  u_OutsetTint;
    float u_OutsetOffset;      // screen coverage, pixel absolute
    float u_OutsetWidth;       // atlas distance, zoom relative
    float u_OutsetBias;        // screen coverage, pixel absolute
    float u_OutsetBlur;        // atlas distance, zoom relative
    float u_InsetRoundness;    // 0 keeps the corner-true field, 1 the smooth one
    float u_InsetThreshold;
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

    vec2   Plane     = (vec2(a_Offset) + Corner * vec2(a_Size)) * GLYPH_SUBPIXEL;
    Affine Transform = ReadAffine(Run.u_Transform0, Run.u_Transform1, Run.u_Transform2);
    vec3   Position  = ApplyAffine(Transform, vec3(Plane, 0.0));

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

// Returns the median of the three MSDF channels, i.e. the reconstructed signed distance.
float Median(vec3 Color)
{
    return max(min(Color.r, Color.g), min(max(Color.r, Color.g), Color.b));
}

// Returns the screen-space scale that maps an atlas distance onto pixel coverage.
float Spread(vec2 Coordinates, vec2 Unit)
{
    return max(dot(Unit, vec2(1.0) / fwidth(Coordinates)) * 0.5, 1.0);
}

void main()
{
    PackedFontParameters Font = u_Parameters[v_Effect];

    vec4  Sample       = texture(t_Albedo, v_Texture);
    float DistanceSDF  = Sample.a;
    float DistanceMSDF = Median(Sample.rgb);

    // Convert atlas distance into normalized screen-space range.
    float Scale = Spread(v_Texture, u_Range);

    // Interpolated distance field depending on rounded vs sharp style.
    float StrokeDistance = mix(DistanceMSDF, DistanceSDF, Font.u_InsetRoundness);
    float StrokeBase     = StrokeDistance - Font.u_InsetThreshold;

    // Convert distance to alpha coverage.
    float InnerStrokeA = Scale * StrokeBase + 0.5 + Font.u_OutsetOffset;
    float OuterStrokeA = Scale * (StrokeBase + Font.u_OutsetWidth) + 0.5 + Font.u_OutsetOffset + Font.u_OutsetBias;

    vec4 InnerColor    = v_Color;
    vec4 OuterColor    = ZyUnpackTint(Font.u_OutsetTint);
    float InnerOpacity = clamp(InnerStrokeA, 0.0, 1.0);
    float OuterOpacity = clamp(OuterStrokeA, 0.0, 1.0);

    // Optional: soften the outset edge.
    float BlurStart  = Font.u_OutsetWidth + Font.u_OutsetBias / Scale;
    float BlurEnd    = BlurStart * (1.0 - Font.u_OutsetBlur);
    float BlurDist   = Font.u_InsetThreshold - DistanceSDF - Font.u_OutsetOffset / Scale;
    float BlurFactor = mix(1.0, 1.0 - smoothstep(BlurEnd, BlurStart, BlurDist), step(0.0001, Font.u_OutsetBlur));

    out_Color = InnerColor * InnerOpacity + (OuterColor * BlurFactor) * max(OuterOpacity - InnerOpacity, 0.0);
}

#endif // FRAGMENT_SHADER