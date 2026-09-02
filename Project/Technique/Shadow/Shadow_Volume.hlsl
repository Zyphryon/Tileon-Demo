// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Resources://Technique/Common/Affine.hlsl"
#include "Resources://Technique/Common/Shadow.hlsl"

cbuffer cb_Pass : register(b1)
{
    float4 u_Caster[kShadowCasters];    // center.xyz, radius
};

static const uint kFacingPartMask  = 15u;
static const uint kFacingSizeShift = 4u;
static const uint kFacingSideShift = kFacingSlotShift + kShadowSlotBits + 1u;
static const uint kFacingSideMask  = 3u;

struct vs_Input
{
    uint   VertexID   : SV_VertexID;

    float4 Transform0 : SLOT0;
    float4 Transform1 : SLOT1;
    float4 Transform2 : SLOT2;

    float3 Size       : SLOT3;    // the ground covered along x and z, and the height reached along y
    uint   Facing     : SLOT4;    // caster slot, wrap copy and which side of the box this is
};

struct fs_Input
{
    float4 Position   : SV_POSITION;
    float  Radial     : TEXCOORD0;    // distance from the caster, over its radius
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

/// Places one corner of a side in the box's own space, over the share of it this draw covers.
float3 PlaceSide(uint Side, float2 Corner, uint Part, uint Parts, float3 Size)
{
    const float2 Half  = float2(Size.x, Size.z) * 0.5;
    const float  Along = (float(Part) + Corner.x) / float(Parts);

    // The footprint stands on the ground it covers, so the box rises from nothing to the height it reaches.
    if (Side < 2u)
    {
        return float3(lerp(-Half.x, Half.x, Along), Corner.y * Size.y, (Side == 0u) ? -Half.y : Half.y);
    }
    return float3((Side == 2u) ? -Half.x : Half.x, Corner.y * Size.y, lerp(-Half.y, Half.y, Along));
}

fs_Input main(vs_Input Input)
{
    fs_Input Result;

    const float2 Corner = ZyEmitRect(Input.VertexID);

    // Only the four upright sides can block anything, and each of them is a quad like any other.
    const uint   Side   = (Input.Facing >> kFacingSideShift) & kFacingSideMask;
    const uint   Part   = Input.Facing & kFacingPartMask;
    const uint   Parts  = ((Input.Facing >> kFacingSizeShift) & kFacingPartMask) + 1u;

    const Affine Transform = ReadAffine(Input.Transform0, Input.Transform1, Input.Transform2);
    const float3 Position  = ApplyAffine(Transform, PlaceSide(Side, Corner, Part, Parts, Input.Size));

    const uint   Slot   = (Input.Facing >> kFacingSlotShift) & kFacingSlotMask;
    const float4 Caster = u_Caster[Slot];

    const float3 Delta  = Position - Caster.xyz;
    const float  Radial = length(Delta.xz);
    const Arc    Where  = ReadArc(Position, Transform.Origin, Caster.xyz);

    float U = Where.Across;

    // The copy carries whatever ran off the end of the map back around to the side it belongs on.
    if ((Input.Facing & kFacingWrap) != 0u)
    {
        float Lowest = 0.0;
        float Widest = 0.0;

        [unroll]
        for (uint Index = 0; Index < 4; ++Index)
        {
            const float3 Local = PlaceSide(Side, ZyEmitRect(Index), Part, Parts, Input.Size);
            const float  Turn  = ShadowSwing(ApplyAffine(Transform, Local), Caster.xyz, Where.Pivot);

            Lowest = min(Lowest, Turn);
            Widest = max(Widest, Turn);
        }

        if (ShadowFits(Where.Anchor, Lowest, Widest))
        {
            // Every corner goes off the map, so the copy covers no area at all.
            Result.Position = kShadowDiscarded;
            Result.Radial   = 0.0;

            return Result;
        }
        U += (Where.Anchor < 0.5) ? 1.0 : -1.0;
    }

    // Indexing by the tangent keeps an upright side's vertical edge straight, since its radius never changes.
    const float Height = ShadowHeight(Delta.y / max(Radial, 0.0001));

    Result.Position = PlaceAtlas(U, ShadowRow(float(Slot), Height));
    Result.Radial   = Radial / max(Caster.w, 0.0001);

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

float main(fs_Input Input) : SV_Target0
{
    // Art drawn with the view already in it has no silhouette to test, so the whole side blocks.
    return saturate(Input.Radial);
}

#endif // FRAGMENT_SHADER