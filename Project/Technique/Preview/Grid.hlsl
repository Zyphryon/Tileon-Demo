// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
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

// Returns the anti-aliased line coverage of the lattice with the given period, at this fragment.
float Coverage(float2 World, float2 Period)
{
    const float2 Repeat   = World / Period;
    const float2 Derivate = max(fwidth(Repeat), 1e-8);
    const float2 Distance = abs(frac(Repeat - 0.5) - 0.5) / Derivate;

    // Once the lines sit closer than a couple of pixels apart they alias into noise, so dissolve them instead.
    const float Density = saturate(1.0 - max(Derivate.x, Derivate.y) * 2.0);
    return saturate(1.0 - min(Distance.x, Distance.y)) * Density;
}

float4 main(fs_Input Input) : SV_Target0
{
    const float Tile   = Coverage(Input.World, float2(1.0, 1.0));
    const float Region = Coverage(Input.World, u_Dimension);

    const float4 Result = lerp(
        float4(kColorTiles.rgb,   kColorTiles.a   * Tile),
        float4(kColorRegions.rgb, kColorRegions.a * Region), Region);

    clip(Result.a - 0.001);
    return Result;
}

#endif // FRAGMENT_SHADER