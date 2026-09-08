// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Resources://Technique/Common/Sprite.glsl"
#include "Resources://Technique/Common/Shadow.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    vec4 u_Caster[kShadowCasters];    // center.xyz, radius
};

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

out vec2  v_Texture;
#ifdef ENABLE_LAYERED
flat out float v_Layer;     // the layer of the material's array the art is read from
#endif

void main()
{
    vec2     Corner    = ZyEmitRect(gl_VertexID);

    // The quad has to stand exactly where the geometry pass draws it, so it is placed the same way.
    ZyAffine Transform = ZyReadAffine(a_Transform0, a_Transform1, a_Transform2);
    Face     Surface   = ReadFace(a_Orientation, Transform);
    vec3     Position  = PlaceCorner(Transform, Surface, Corner, a_Size);

    // The caster the quad is unwrapped around, and which band of the atlas it lands in.
    uint Slot   = (a_Orientation >> kFacingSlotShift) & kFacingSlotMask;
    vec4 Caster = u_Caster[Slot];

    vec3  Delta  = Position - Caster.xyz;
    float Radial = length(Delta.xz);
    Arc   Where  = ReadArc(Position, Transform.Origin, Caster.xyz);

    float U = Where.Across;

    if ((a_Orientation & kFacingWrap) != 0u)
    {
        // Most quads sit well inside the band, so the copy steps aside when every corner already lands.
        float Lowest = 0.0;
        float Widest = 0.0;

        for (int Index = 0; Index < 4; ++Index)
        {
            vec3  Point = PlaceCorner(Transform, Surface, ZyEmitRect(Index), a_Size);
            float Turn  = ShadowSwing(Point, Caster.xyz, Where.Pivot);

            Lowest = min(Lowest, Turn);
            Widest = max(Widest, Turn);
        }

        if (ShadowFits(Where.Anchor, Lowest, Widest))
        {
            gl_Position = kShadowDiscarded;
            v_Texture   = vec2(0.0);

            return;
        }
        U += (Where.Anchor < 0.5) ? 1.0 : -1.0;
    }

    // Indexing by the tangent keeps a standing quad's vertical edge straight, since its radius never changes.
    float Height = ShadowHeight(Delta.y / max(Radial, 0.0001));

    gl_Position   = PlaceAtlas(U, ShadowRow(float(Slot), Height));
    gl_Position.z = (Radial / max(Caster.w, 0.0001)) * 2.0 - 1.0;
    v_Texture     = mix(a_Frame.xy, a_Frame.zw, ReadSample(a_Orientation, Corner));
#ifdef ENABLE_LAYERED
    v_Layer       = float(a_Orientation >> kLayerShift);
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

in vec2  v_Texture;
#ifdef ENABLE_LAYERED
flat in float v_Layer;
#endif


void main()
{
    // The art's own cutout is the blocker, so a gap in the canopy lets the light straight through.
#ifdef ENABLE_LAYERED
    if (texture(t_Albedo, vec3(v_Texture, v_Layer)).a < 0.5)
#else
    if (texture(t_Albedo, v_Texture).a < 0.5)
#endif
    {
        discard;
    }
}

#endif // FRAGMENT_SHADER