// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Embedded://Shader/Affine.hlsl"

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

    const float2   Corner    = ZyEmitRect(Input.VertexID);
    const ZyAffine Transform = ZyReadAffine(Input.Transform0, Input.Transform1, Input.Transform2);
    const float3   Position  = ZyApplyAffine(Transform, PlaceFace(Input.Face, Corner, Input.Size));

    // The map is a plain depth buffer, so the distance along the sun is what the rasterizer already keeps.
    Result.Position = mul(u_Sunlight, float4(Position, 1.0));

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

/// The map keeps the nearest blocker, which the depth test settles on its own.
void main(fs_Input Input)
{
}

#endif // FRAGMENT_SHADER