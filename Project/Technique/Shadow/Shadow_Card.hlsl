// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Resources://Technique/Common/Sprite.hlsl"
#include "Resources://Technique/Common/Shadow.hlsl"

cbuffer cb_Pass : register(b1)
{
    float4 u_Caster[kShadowCasters];    // center.xyz, radius
};

struct vs_Input
{
    uint   VertexID   : SV_VertexID;

    float4 Transform0  : SLOT0;
    float4 Transform1  : SLOT1;
    float4 Transform2  : SLOT2;
    float4 Frame       : SLOT3;
    float2 Size        : SLOT4;
    float4 Color       : SLOT5;
    uint   Orientation : SLOT6;
};

struct fs_Input
{
    float4 Position   : SV_POSITION;
    float2 Texture    : TEXCOORD0;
    float  Radial     : TEXCOORD1;    // distance from the caster, over its radius
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(vs_Input Input)
{
    fs_Input Result;

    const float2 Corner    = ZyEmitRect(Input.VertexID);

    // The quad has to stand exactly where the geometry pass draws it, so it is placed the same way.
    const Affine Transform = ReadAffine(Input.Transform0, Input.Transform1, Input.Transform2);
    const Face   Surface   = ReadFace(Input.Orientation, Transform);
    const float3 Position  = PlaceCorner(Transform, Surface, Corner, Input.Size);

    // The caster the quad is unwrapped around, and which band of the atlas it lands in.
    const uint   Slot   = (Input.Orientation >> kFacingSlotShift) & kFacingSlotMask;
    const float4 Caster = u_Caster[Slot];

    const float3 Delta  = Position - Caster.xyz;
    const float  Radial = length(Delta.xz);
    const Arc    Where  = ReadArc(Position, Transform.Origin, Caster.xyz);

    float U = Where.Across;

    if ((Input.Orientation & kFacingWrap) != 0u)
    {
        // Most quads sit well inside the band and have nothing to carry, so the copy measures the whole
        // quad and steps aside when every corner of it already lands on the map.
        float Lowest = 0.0;
        float Widest = 0.0;

        [unroll]
        for (uint Index = 0; Index < 4; ++Index)
        {
            const float3 Point = PlaceCorner(Transform, Surface, ZyEmitRect(Index), Input.Size);
            const float  Turn  = ShadowSwing(Point, Caster.xyz, Where.Pivot);

            Lowest = min(Lowest, Turn);
            Widest = max(Widest, Turn);
        }

        if (ShadowFits(Where.Anchor, Lowest, Widest))
        {
            Result.Position = kShadowDiscarded;
            Result.Texture  = float2(0.0, 0.0);
            Result.Radial   = 0.0;

            return Result;
        }
        U += (Where.Anchor < 0.5) ? 1.0 : -1.0;
    }

    // Indexing by the tangent keeps a standing quad's vertical edge straight, since its radius never changes.
    const float Height = ShadowHeight(Delta.y / max(Radial, 0.0001));

    Result.Position = PlaceAtlas(U, ShadowRow(float(Slot), Height));
    Result.Texture  = lerp(Input.Frame.xy, Input.Frame.zw, ReadSample(Input.Orientation, Corner));
    Result.Radial   = Radial / max(Caster.w, 0.0001);

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

Texture2D    t_Albedo : register(t0);
SamplerState s_Albedo : register(s0);

float main(fs_Input Input) : SV_Target0
{
    // The art's own cutout is the blocker, so a gap in the canopy lets the light straight through.
    clip(t_Albedo.Sample(s_Albedo, Input.Texture).a - 0.5);

    return saturate(Input.Radial);
}

#endif // FRAGMENT_SHADER