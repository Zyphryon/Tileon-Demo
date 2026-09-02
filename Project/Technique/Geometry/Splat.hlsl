// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Embedded://Shader/Packing.hlsl"
#include "Embedded://Shader/Noise.hlsl"
#include "Resources://Technique/Common/Scene.hlsl"

struct vs_Input
{
    uint   VertexID  : SV_VertexID;

    int2   Origin    : SLOT0;    // region corner, in units, relative to the frame's origin
    uint   Weights   : SLOT1;    // slice of the weight array, and above it how many slots it blends
    uint4  Palette   : SLOT2;    // slice of the terrain array each of the four slots draws
    float4 Mapping   : SLOT3;    // how often each slot repeats across one world unit
    float4 Phase0    : SLOT4;    // where slots 0 and 1 already stand in their repeat, at the region's corner
    float4 Phase1    : SLOT5;    // the same, for slots 2 and 3
    uint4  Tint      : SLOT6;    // the color each slot's art is multiplied by, packed as RGBA8
    float4 Feather   : SLOT7;    // how wide a band each slot's relief feathers over
};

struct fs_Input
{
    float4                 Position : SV_POSITION;
    float2                 Ground   : TEXCOORD0;
    nointerpolation uint   Weights  : TEXCOORD1;
    nointerpolation uint   Count    : TEXCOORD2;
    nointerpolation uint4  Palette  : TEXCOORD3;
    nointerpolation float4 Mapping  : TEXCOORD4;
    nointerpolation float4 Phase[2] : TEXCOORD5;
    nointerpolation float4 Tint[4]  : TEXCOORD7;
    nointerpolation float4 Feather  : TEXCOORD11;
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(vs_Input Input)
{
    fs_Input Result;

    const float2 Corner = ZyEmitRect(Input.VertexID);
    const float2 Unit   = float2(Input.Origin) + Corner * SPLAT_UNITS_PER_REGION;

    Result.Position = mul(u_Camera, float4(Unit.x, 0.0, Unit.y, 1.0));
    Result.Ground   = Corner;
    Result.Weights  = Input.Weights & 0xFFFF;
    Result.Count    = Input.Weights >> 16;
    Result.Palette  = Input.Palette;
    Result.Mapping  = Input.Mapping * SPLAT_UNITS_PER_REGION;
    Result.Phase[0] = Input.Phase0;
    Result.Phase[1] = Input.Phase1;
    Result.Tint[0]  = ZyUnpackTint(Input.Tint.x);
    Result.Tint[1]  = ZyUnpackTint(Input.Tint.y);
    Result.Tint[2]  = ZyUnpackTint(Input.Tint.z);
    Result.Tint[3]  = ZyUnpackTint(Input.Tint.w);

    Result.Feather  = Input.Feather;

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

Texture2DArray t_Weight : register(t0);
SamplerState   s_Weight : register(s0);
Texture2DArray t_Albedo : register(t1);
SamplerState   s_Albedo : register(s1);
#ifdef ENABLE_NORMAL_MAPPING
Texture2DArray t_Normal : register(t2);
SamplerState   s_Normal : register(s2);
#endif

struct fs_Output
{
    float4 Albedo : SV_Target0;
    float4 Normal : SV_Target1;
};

fs_Output main(fs_Input Input)
{
    fs_Output Result;

    const float  Size    = SPLAT_UNITS_PER_REGION + 2.0 * SPLAT_MAP_BORDER;
    const float2 Sampled = (Input.Ground * SPLAT_UNITS_PER_REGION + SPLAT_MAP_BORDER) / Size;

    float4 Weight = t_Weight.Sample(s_Weight, float3(Sampled, Input.Weights));

    clip(dot(Weight, float4(1.0, 1.0, 1.0, 1.0)) - SPLAT_WEIGHT_FLOOR);

    Weight /= max(dot(Weight, float4(1.0, 1.0, 1.0, 1.0)), 0.0001);

    float2 Texture[4];
    float4 Source[4];
#ifdef ENABLE_HEIGHT_BLEND
    float4 Height = float4(0.0, 0.0, 0.0, 0.0);
#endif
#ifdef ENABLE_NORMAL_MAPPING
    float3 Tangent[4];
#endif

    // Every fetch the pixel takes is issued here, ahead of all the math, so one hides the latency of the next.
    [unroll]
    for (uint Slot = 0; Slot < 4; ++Slot)
    {
        if (Slot < Input.Count)
        {
            const float2 Sweep = (Slot & 1) ? Input.Phase[Slot >> 1].zw : Input.Phase[Slot >> 1].xy;

            Texture[Slot] = Sweep + Input.Ground * Input.Mapping[Slot];
            Source[Slot]  = t_Albedo.Sample(s_Albedo, float3(Texture[Slot], Input.Palette[Slot]));

#ifdef ENABLE_HEIGHT_BLEND
            Height[Slot] = Source[Slot].a
                + (ZyValueNoise(Texture[Slot] * SPLAT_RELIEF_SCALE) - 0.5) * SPLAT_RELIEF_STRENGTH;
#endif

#ifdef ENABLE_NORMAL_MAPPING
            Tangent[Slot] = ZyDecodeNormalMap(t_Normal.Sample(s_Normal, float3(Texture[Slot], Input.Palette[Slot])).xyz);
#endif
        }
    }

#ifdef ENABLE_HEIGHT_BLEND
    // Each terrain feathers over a band of its own, mixed by how much of the pixel it already covers.
    const float Band = max(dot(Input.Feather, Weight), 0.001);

    const float4 Raised = (Height + Weight) * step(SPLAT_WEIGHT_FLOOR, Weight);

    Weight  = max(Raised - (max(max(Raised.x, Raised.y), max(Raised.z, Raised.w)) - Band), 0.0);
    Weight /= max(dot(Weight, float4(1.0, 1.0, 1.0, 1.0)), 0.0001);
#endif

    float3 Albedo = float3(0.0, 0.0, 0.0);
    float2 Slope  = float2(0.0, 0.0);

    [unroll]
    for (uint Layer = 0; Layer < 4; ++Layer)
    {
        if (Layer >= Input.Count)
        {
            continue;
        }

        Albedo += Source[Layer].rgb * Input.Tint[Layer].rgb * Weight[Layer];

#ifdef ENABLE_NORMAL_MAPPING
        // Averaging unit normals pulls a meeting toward flat, so the slopes each one stands at are mixed.
        Slope += Tangent[Layer].xy * (rcp(max(Tangent[Layer].z, 0.0001)) * Weight[Layer]);
#endif
    }

    Result.Albedo = float4(Albedo, 0.0);

#ifdef ENABLE_NORMAL_MAPPING
    // The ground faces up, so the slope runs along the plane and world up stands at one.
    const float3 Surface = normalize(float3(Slope.x, 1.0, Slope.y));
    Result.Normal = float4(ZyEncodeNormalMap(Surface), 1.0);
#else
    Result.Normal = float4(ZyEncodeNormalMap(float3(0.0, 1.0, 0.0)), 1.0);
#endif

    return Result;
}

#endif // FRAGMENT_SHADER