// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Resources://Technique/Common/Affine.hlsl"

cbuffer cb_Pass : register(b1)
{
    float4x4 u_Sunlight;    // Turns world space into the sun's own clip space.
};

struct vs_Input
{
    uint   VertexID   : SV_VertexID;

    float4 Transform0 : SLOT0;
    float4 Transform1 : SLOT1;
    float4 Transform2 : SLOT2;
    float3 Size       : SLOT3;    // the ground covered along x and z, and the height reached along y
    uint   Face       : SLOT4;    // which face of the box this quad stands for
};

struct fs_Input
{
    float4 Position   : SV_POSITION;
    float  Along      : TEXCOORD0;    // how far along the sun the face stands, over the map's own span
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

float3 PlaceFace(uint Face, float2 Corner, float3 Size)
{
    const float2 Half = float2(Size.x, Size.z) * 0.5;

    if (Face >= 4u)
    {
        return float3(lerp(-Half.x, Half.x, Corner.x), Size.y, lerp(-Half.y, Half.y, Corner.y));
    }

    if (Face < 2u)
    {
        return float3(lerp(-Half.x, Half.x, Corner.x), Corner.y * Size.y, (Face == 0u) ? -Half.y : Half.y);
    }

    return float3((Face == 2u) ? -Half.x : Half.x, Corner.y * Size.y, lerp(-Half.y, Half.y, Corner.x));
}

fs_Input main(vs_Input Input)
{
    fs_Input Result;

    const float2 Corner    = ZyEmitRect(Input.VertexID);
    const Affine Transform = ReadAffine(Input.Transform0, Input.Transform1, Input.Transform2);
    const float3 Position  = ApplyAffine(Transform, PlaceFace(Input.Face, Corner, Input.Size));

    // The sun's own camera is orthographic, so the clip depth is already the distance along it, over one.
    const float4 Clip = mul(u_Sunlight, float4(Position, 1.0));

    Result.Position = Clip;
    Result.Along    = Clip.z;

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

/// The map keeps the nearest blocker, which the technique's own minimum blend is what settles.
float main(fs_Input Input) : SV_Target0
{
    return saturate(Input.Along);
}

#endif // FRAGMENT_SHADER