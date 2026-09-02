// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Embedded://Shader/Depth.hlsl"
#include "Embedded://Shader/Packing.hlsl"
#include "Resources://Technique/Common/Sprite.hlsl"

static const float kCoplanarLift = 0.01;

#ifdef ENABLE_RELIEF
cbuffer cb_Material : register(b2)
{
    float2 u_Relief;    // X = The level the greyscale calls the quad, Y = How far below it reaches, in world units
};
#endif

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
#ifdef ENABLE_RELIEF
    noperspective centroid
#endif
    float4 Position   : SV_POSITION;
    float2 Texture    : TEXCOORD0;
    float4 Color      : COLOR0;
#ifdef ENABLE_NORMAL_MAPPING
    float3 AxisX      : TEXCOORD1;
    float3 AxisY      : TEXCOORD2;
#endif
    float3 AxisZ      : TEXCOORD3;   // the face the art turns towards, pointing out of it
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(vs_Input Input)
{
    fs_Input Result;

    const float2 Corner    = ZyEmitRect(Input.VertexID);
    const Affine Transform = ReadAffine(Input.Transform0, Input.Transform1, Input.Transform2);
    const Face   Surface   = ReadFace(Input.Orientation, Transform);

    Result.Position = mul(u_Camera, float4(PlaceCorner(Transform, Surface, Corner, Input.Size), 1.0));

    // Art laid against the ground is coplanar with it, and would z-fight it without a nudge forward.
    if (Surface.Plane == kPlaneGround)
    {
        const float Along = ZyDepthSpan(u_CameraInverse);

#ifdef ENABLE_RELIEF
        Result.Position.z -= u_Relief.y / Along;
#endif

        Result.Position.z -= kCoplanarLift / Along;
    }

    Result.Texture  = lerp(Input.Frame.xy, Input.Frame.zw, ReadSample(Input.Orientation, Corner));
    Result.Color    = Input.Color;

#ifdef ENABLE_NORMAL_MAPPING
    Result.AxisX = normalize(Surface.AxisU);
    Result.AxisY = normalize(Surface.AxisV);
#endif

    Result.AxisZ = normalize(Surface.Normal);

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

Texture2D    t_Albedo : register(t0);
SamplerState s_Albedo : register(s0);

#ifdef ENABLE_NORMAL_MAPPING
Texture2D    t_Normal : register(t1);
SamplerState s_Normal : register(s1);
#endif

#ifdef ENABLE_RELIEF
Texture2D    t_Relief : register(t2);
SamplerState s_Relief : register(s2);

// Returns how far below the quad the greyscale sinks this texel, in world units.
float ReliefSink(float2 Texture)
{
    return saturate(u_Relief.x - t_Relief.Sample(s_Relief, Texture).r) * u_Relief.y;
}
#endif

#ifdef ENABLE_ALPHA_TEST

struct fs_Output
{
    float4 Albedo : SV_Target0;
    float4 Normal : SV_Target1;
#ifdef ENABLE_RELIEF
    float  Depth  : SV_DepthGreaterEqual;
#endif
};

fs_Output main(fs_Input Input)
{
    fs_Output Result;

    const float4 Texel = t_Albedo.Sample(s_Albedo, Input.Texture);

    clip(Texel.a - 0.5);

#ifdef ENABLE_RELIEF
    const float Sink = ReliefSink(Input.Texture);
#else
    const float Sink = 0.0;
#endif

    Result.Albedo = float4(Input.Color.rgb * Texel.rgb, saturate(Sink / kReliefRange));

#ifdef ENABLE_NORMAL_MAPPING
    const float3 Tangent = normalize(ZyDecodeNormalMap(t_Normal.Sample(s_Normal, Input.Texture).rgb));
    const float3 Normal  = normalize(Tangent.x * Input.AxisX + Tangent.y * Input.AxisY + Tangent.z * Input.AxisZ);
#else
    const float3 Normal  = Input.AxisZ;
#endif

    // The two bits the normal buffer has left over carry nothing, so they are written full.
    Result.Normal = float4(ZyEncodeNormalMap(Normal), 1.0);

#ifdef ENABLE_RELIEF
    Result.Depth = Input.Position.z + Sink / ZyDepthSpan(u_CameraInverse);
#endif

    return Result;
}

#else

struct fs_Output
{
    float4 Color : SV_Target0;
#ifdef ENABLE_RELIEF
    float  Depth : SV_DepthGreaterEqual;
#endif
};

// Transparent sprites blend into the lit scene, so they write one target and take no lighting.
fs_Output main(fs_Input Input)
{
    fs_Output Result;

    Result.Color = Input.Color * t_Albedo.Sample(s_Albedo, Input.Texture);

#ifdef ENABLE_RELIEF
    Result.Depth = Input.Position.z + ReliefSink(Input.Texture) / ZyDepthSpan(u_CameraInverse);
#endif

    return Result;
}

#endif // ENABLE_ALPHA_TEST

#endif // FRAGMENT_SHADER