// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Resources://Technique/Common/Scene.hlsl"

struct vs_Input
{
    uint   VertexID : SV_VertexID;
    float3 Center   : SLOT0;
    float3 Extent   : SLOT1;
    float4 Tint     : SLOT2;
};

struct fs_Input
{
    float4 Position : SV_POSITION;
    float4 Tint     : COLOR0;
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(vs_Input Input)
{
    fs_Input Result;

#ifdef BOUNDARY_FLAT

    // A flat boundary is the screen rectangle the volume covers, so it is bounded in clip space instead.
    const float4 Origin = mul(u_Camera, float4(Input.Center, 1.0));
    const float2 Span   = abs(mul(u_Camera, float4(Input.Extent.x, 0.0, 0.0, 0.0)).xy)
                        + abs(mul(u_Camera, float4(0.0, Input.Extent.y, 0.0, 0.0)).xy)
                        + abs(mul(u_Camera, float4(0.0, 0.0, Input.Extent.z, 0.0)).xy);

    Result.Position = float4(Origin.xy + ZyEmitQuadEdges(Input.VertexID) * Span, Origin.zw);

#else

    Result.Position = mul(u_Camera, float4(Input.Center + ZyEmitBox(Input.VertexID) * Input.Extent, 1.0));

#endif // BOUNDARY_FLAT

    Result.Tint = Input.Tint;

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

float4 main(fs_Input Input) : SV_Target0
{
    return Input.Tint;
}

#endif // FRAGMENT_SHADER