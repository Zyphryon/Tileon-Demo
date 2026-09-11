// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Resources://Technique/Common/Sprite.glsl"

#ifdef ENABLE_LAYERED
layout(binding = 0) uniform sampler2DArray t_Albedo;
#else
layout(binding = 0) uniform sampler2D      t_Albedo;
#endif

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

layout(location = 0) in vec4 a_Transform0;
layout(location = 1) in vec4 a_Transform1;
layout(location = 2) in vec4 a_Transform2;

layout(location = 3) in vec4 a_Frame;
layout(location = 4) in vec2 a_Size;
layout(location = 5) in vec4 a_Color;
layout(location = 6) in uint a_Orientation;

out vec2       v_Texture;
out vec4       v_Color;
flat out float v_Stroke;    // how many pixels of art the stroke stands out from the shape it rings
flat out vec4  v_Frame;     // the crop the art was taken from, which the stroke may not reach past

#ifdef ENABLE_LAYERED
flat out float v_Layer;     // the layer of the material's array the art is read from
#endif

void main()
{
    vec2     Corner    = ZyEmitRect(gl_VertexID);
    ZyAffine Transform = ZyReadAffine(a_Transform0, a_Transform1, a_Transform2);
    Face     Surface   = ReadFace(a_Orientation, Transform);

    // The card is grown by the stroke it carries, since a ring standing outside the art needs room the art's
    // own crop does not have; the corners are pushed out from the middle, so the art stays where it stood.
    float Stroke = float((a_Orientation >> kStrokeShift) & kStrokeMask);
    vec2  Crop   = abs(a_Frame.zw - a_Frame.xy) * vec2(textureSize(t_Albedo, 0).xy);
    vec2  Spread = (Crop + 2.0 * Stroke) / max(Crop, vec2(1.0));

    Corner = (Corner - 0.5) * Spread + 0.5;

    gl_Position = u_Camera * vec4(PlaceCorner(Transform, Surface, Corner, a_Size), 1.0);

    // The stroke rings art that is already drawn, so it stands a hair nearer to keep off the seam it traces.
    gl_Position.z -= 0.02 * u_ScreenX.w;

    vec2 Repeat = (a_Orientation & kTiled) != 0u
        ? vec2(length(Surface.AxisU), length(Surface.AxisV))
        : vec2(1.0);

    v_Texture = a_Frame.xy + (a_Frame.zw - a_Frame.xy) * (ReadSample(a_Orientation, Corner) * Repeat);
    v_Color   = a_Color;
    v_Stroke  = float((a_Orientation >> kStrokeShift) & kStrokeMask);
    v_Frame   = a_Frame;

#ifdef ENABLE_LAYERED
    v_Layer = float(a_Orientation >> kLayerShift);
#endif
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

in vec2       v_Texture;
in vec4       v_Color;
flat in float v_Stroke;
flat in vec4  v_Frame;

#ifdef ENABLE_LAYERED
flat in float v_Layer;
#define OutlineRead(Texture) textureLod(t_Albedo, vec3(Texture, v_Layer), 0.0).a
#else
#define OutlineRead(Texture) textureLod(t_Albedo, Texture, 0.0).a
#endif

layout(location = 0) out vec4 out_Albedo;

/// Reads how much of a point the art fills, counting anything past its own crop as empty.
float Coverage(vec2 Texture)
{
    // A crop sits in an atlas beside art it knows nothing about, so a stroke that read past it would ring
    // whatever happened to be packed alongside.
    if (any(lessThan(Texture, v_Frame.xy)) || any(greaterThan(Texture, v_Frame.zw)))
    {
        return 0.0;
    }
    return OutlineRead(Texture);
}

void main()
{
    const vec2  Step   = 1.0 / vec2(textureSize(t_Albedo, 0).xy);
    const float Inside = Coverage(v_Texture);
    const int   Reach  = int(v_Stroke);

    // The nearest art is what the ring is drawn from, and it is worth less the further out it was found, so
    // the band falls away toward its rim rather than ending on a step.
    float Strength = 0.0;

    for (int Index = 1; Index <= Reach; ++Index)
    {
        const float Span = float(Index);
        const float Fade = 1.0 - (Span - 1.0) / max(float(Reach), 1.0);
        const vec2  Away = Step * Span;
        const vec2  Bias = Away * 0.70710678;

        float Found = max(max(Coverage(v_Texture + vec2( Away.x, 0.0)),
                              Coverage(v_Texture + vec2(-Away.x, 0.0))),
                          max(Coverage(v_Texture + vec2(0.0,  Away.y)),
                              Coverage(v_Texture + vec2(0.0, -Away.y))));

        // The corners are asked as well, or the ring would come to a cross where the art turns.
        Found = max(Found, max(max(Coverage(v_Texture + vec2( Bias.x,  Bias.y)),
                                   Coverage(v_Texture + vec2(-Bias.x,  Bias.y))),
                               max(Coverage(v_Texture + vec2( Bias.x, -Bias.y)),
                                   Coverage(v_Texture + vec2(-Bias.x, -Bias.y)))));

        Strength = max(Strength, Found * Fade);
    }

    // What the art already fills is the art's, so the ring gives way as it meets it rather than cutting.
    const float Alpha = clamp(Strength, 0.0, 1.0) * (1.0 - Inside);

    if (Alpha <= 0.0)
    {
        discard;
    }
    out_Albedo = vec4(v_Color.rgb, v_Color.a * Alpha);
}
#endif // FRAGMENT_SHADER