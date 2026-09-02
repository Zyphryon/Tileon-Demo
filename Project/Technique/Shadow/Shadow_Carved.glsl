// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Resources://Technique/Common/Sprite.glsl"
#include "Resources://Technique/Common/Shadow.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    vec4 u_Caster[kShadowCasters];    // center.xyz, radius
};

const uint kFacingPartMask   = 15u;
const uint kFacingSizeShift  = 4u;
const uint kFacingSideShift  = kFacingSlotShift + kShadowSlotBits + 1u;
const uint kFacingSideMask   = 3u;
const uint kFacingMirrorShift = kFacingSideShift + 2u;

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

layout(location = 0) in vec4 a_Transform0;
layout(location = 1) in vec4 a_Transform1;
layout(location = 2) in vec4 a_Transform2;
layout(location = 3) in vec3 a_Size;
layout(location = 4) in uint a_Facing;
layout(location = 5) in vec4 a_Frame;

out vec2  v_Texture;
out float v_Radial;

/// Places one corner of a side in the box's own space, over the share of it this draw covers.
vec3 PlaceSide(uint Side, vec2 Corner, uint Part, uint Parts, vec3 Size)
{
    vec2  Half  = vec2(Size.x, Size.z) * 0.5;
    float Along = (float(Part) + Corner.x) / float(Parts);

    // The footprint stands on the ground it covers, so the box rises from nothing to the height it reaches.
    if (Side < 2u)
    {
        return vec3(mix(-Half.x, Half.x, Along), Corner.y * Size.y, (Side == 0u) ? -Half.y : Half.y);
    }
    return vec3((Side == 2u) ? -Half.x : Half.x, Corner.y * Size.y, mix(-Half.y, Half.y, Along));
}

void main()
{
    vec2 Corner = ZyEmitRect(gl_VertexID);

    // Only the four upright sides can block anything, and each of them is a quad like any other.
    uint Side  = (a_Facing >> kFacingSideShift) & kFacingSideMask;
    uint Part  = a_Facing & kFacingPartMask;
    uint Parts = ((a_Facing >> kFacingSizeShift) & kFacingPartMask) + 1u;

    Affine Transform = ReadAffine(a_Transform0, a_Transform1, a_Transform2);
    vec3   Position  = ApplyAffine(Transform, PlaceSide(Side, Corner, Part, Parts, a_Size));

    uint Slot   = (a_Facing >> kFacingSlotShift) & kFacingSlotMask;
    vec4 Caster = u_Caster[Slot];

    vec3  Delta  = Position - Caster.xyz;
    float Radial = length(Delta.xz);
    Arc   Where  = ReadArc(Position, Transform.Origin, Caster.xyz);

    float U = Where.Across;

    // The copy carries whatever ran off the end of the map back around to the side it belongs on.
    if ((a_Facing & kFacingWrap) != 0u)
    {
        float Lowest = 0.0;
        float Widest = 0.0;

        for (int Index = 0; Index < 4; ++Index)
        {
            vec3  Local = PlaceSide(Side, ZyEmitRect(Index), Part, Parts, a_Size);
            float Turn  = ShadowSwing(ApplyAffine(Transform, Local), Caster.xyz, Where.Pivot);

            Lowest = min(Lowest, Turn);
            Widest = max(Widest, Turn);
        }

        if (ShadowFits(Where.Anchor, Lowest, Widest))
        {
            // Every corner goes off the map, so the copy covers no area at all.
            gl_Position = kShadowDiscarded;
            v_Texture   = vec2(0.0);
            v_Radial    = 0.0;

            return;
        }
        U += (Where.Anchor < 0.5) ? 1.0 : -1.0;
    }

    // The side runs across its own slice of the art, whatever the box it stands on measures, so the
    // whole crop is always covered and a doorway anywhere in it lets the light straight through.
    float Along  = (float(Part) + Corner.x) / float(Parts);
    vec2  Sample = ReadSample(a_Facing >> kFacingMirrorShift, vec2(Along, Corner.y));

    // Indexing by the tangent keeps an upright side's vertical edge straight, since its radius never changes.
    float Height = ShadowHeight(Delta.y / max(Radial, 0.0001));

    gl_Position = PlaceAtlas(U, ShadowRow(float(Slot), Height));
    v_Texture   = mix(a_Frame.xy, a_Frame.zw, Sample);
    v_Radial    = Radial / max(Caster.w, 0.0001);
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

layout(binding = 0) uniform sampler2D t_Albedo;

in vec2  v_Texture;
in float v_Radial;

layout(location = 0) out float out_Radial;

void main()
{
    // The art's own cutout is the blocker, so a window in the wall lets the light straight through.
    if (texture(t_Albedo, v_Texture).a < 0.5)
    {
        discard;
    }

    out_Radial = clamp(v_Radial, 0.0, 1.0);
}

#endif // FRAGMENT_SHADER