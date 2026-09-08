// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Embedded://Shader/Grid.hlsl"
#include "Resources://Technique/Common/Scene.hlsl"

cbuffer cb_Pass : register(b1)
{
    float2   u_Dimension;
};

static const float4 kColorTiles   = float4(1.00, 1.00, 1.00, 0.10);
static const float4 kColorRegions = float4(0.100482, 0.522522, 1.000000, 0.60);

struct fs_Input
{
    float4 Position : SV_POSITION;
    float2 World    : TEXCOORD0;
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(uint ID : SV_VertexID)
{
    fs_Input Result;

    Result.Position = float4(ZyEmitScreen(ID).xy, 0.0, 1.0);

    const float4 Head = mul(u_CameraInverse, float4(Result.Position.xy, 0.0, 1.0));
    const float4 Tail = mul(u_CameraInverse, float4(Result.Position.xy, 1.0, 1.0));

    const float3 Origin    = Head.xyz / Head.w;
    const float3 Direction = Tail.xyz / Tail.w - Origin;

    Result.World = (Origin - Direction * (Origin.y / Direction.y)).xz;

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

float4 main(fs_Input Input) : SV_Target0
{
    const float Tile   = ZyGridLine(Input.World);
    const float Region = ZyGridLine(Input.World / u_Dimension);

    const float4 Result = lerp(
        float4(kColorTiles.rgb,   kColorTiles.a   * Tile),
        float4(kColorRegions.rgb, kColorRegions.a * Region), Region);

    clip(Result.a - 0.001);
    return Result;
}

#endif // FRAGMENT_SHADER