// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Resources://Technique/Common/Affine.hlsl"
#include "Resources://Technique/Common/Sprite.hlsl"

cbuffer cb_Pass : register(b1)
{
    float4x4 u_Sunlight;    // Turns world space into the sun's own clip space.
};

/// How far the way the art is turned is shifted up into the side's packed word.
static const uint kSideMirrorShift = 2u;

/// The bits naming which upright side the quad stands for.
static const uint kSideMask        = 3u;

struct vs_Input
{
    uint   VertexID   : SV_VertexID;

    float4 Transform0 : SLOT0;
    float4 Transform1 : SLOT1;
    float4 Transform2 : SLOT2;
    float3 Size       : SLOT3;    // the ground covered along x and z, and the height reached along y
    uint   Side       : SLOT4;    // which upright side this quad stands for, and how the art is turned
    float4 Frame      : SLOT5;    // the art's crop within the sheet it is packed in
};

struct fs_Input
{
    float4 Position   : SV_POSITION;
    float  Along      : TEXCOORD0;    // how far along the sun the side stands, over the map's own span
    float2 Texture    : TEXCOORD1;    // the texel of the art the side is cut out by
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

/// \brief Places one corner of an upright side of the box the art stands in.
///
/// \param Side   The side to place, counted the way the sweep counts them.
/// \param Corner The corner to place, over zero through one on both axes.
/// \param Size   The ground the box covers along x and z, and the height it rises to along y.
/// \return The corner, in the space the box is laid down from.
float3 PlaceSide(uint Side, float2 Corner, float3 Size)
{
    const float2 Half = float2(Size.x, Size.z) * 0.5;

    if (Side < 2u)
    {
        return float3(lerp(-Half.x, Half.x, Corner.x), Corner.y * Size.y, (Side == 0u) ? -Half.y : Half.y);
    }

    return float3((Side == 2u) ? -Half.x : Half.x, Corner.y * Size.y, lerp(-Half.y, Half.y, Corner.x));
}

fs_Input main(vs_Input Input)
{
    fs_Input Result;

    const uint   Side      = Input.Side & kSideMask;
    const float2 Corner    = ZyEmitRect(Input.VertexID);
    const Affine Transform = ReadAffine(Input.Transform0, Input.Transform1, Input.Transform2);
    const float3 Position  = ApplyAffine(Transform, PlaceSide(Side, Corner, Input.Size));

    // The sun's own camera is orthographic, so the clip depth is already the distance along it, over one.
    const float4 Clip = mul(u_Sunlight, float4(Position, 1.0));

    // The side reads the art straight across its own run, which is what cuts it to the outline it was drawn with.
    const float2 Sample = ReadSample(Input.Side >> kSideMirrorShift, Corner);

    Result.Position = Clip;
    Result.Along    = Clip.z;
    Result.Texture  = lerp(Input.Frame.xy, Input.Frame.zw, Sample);

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

Texture2D    t_Albedo : register(t0);
SamplerState s_Albedo : register(s0);

/// The map keeps the nearest blocker, which the technique's own minimum blend is what settles.
float main(fs_Input Input) : SV_Target0
{
    clip(t_Albedo.Sample(s_Albedo, Input.Texture).a - 0.5);

    return saturate(Input.Along);
}

#endif // FRAGMENT_SHADER