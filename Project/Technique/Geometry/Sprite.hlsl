// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
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
#ifdef ENABLE_BLOCK
    float4 Block       : SLOT7;    // where the box rises from, in the sprite's own units, and how high it reaches
    float2 Girth       : SLOT8;    // how wide and how deep the box runs, in the sprite's own units
#endif
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
#ifdef ENABLE_LAYERED
    nointerpolation float Layer : TEXCOORD10;   // the layer of the material's array the art is read from
#endif
#ifdef ENABLE_BLOCK
    float3 Local      : TEXCOORD4;   // the point of the card this pixel stands at, in the box's own frame
    nointerpolation float3 Inverse : TEXCOORD5;   // the reciprocal of the line of sight in that frame
    nointerpolation float3 Half    : TEXCOORD6;   // half the width, the whole height, and half the depth of the box
    nointerpolation float3 FaceX   : TEXCOORD7;   // each face's normal, already turned against the line of sight
    nointerpolation float3 FaceY   : TEXCOORD8;
    nointerpolation float3 FaceZ   : TEXCOORD9;
#endif
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(vs_Input Input)
{
    fs_Input Result;

    const float2   Corner    = ZyEmitRect(Input.VertexID);
    const ZyAffine Transform = ZyReadAffine(Input.Transform0, Input.Transform1, Input.Transform2);
    const Face     Surface   = ReadFace(Input.Orientation, Transform);

    float3 World = PlaceCorner(Transform, Surface, Corner, Input.Size);

#ifdef ENABLE_BLOCK
    // An edge-on run's art is the top of its box, so its card lies on the box rather than on the ground: a segment
    // then draws its own top to its very end, and the front of the segment beyond is never seen through the seam.
    if (Surface.Edge)
    {
        World += Transform.ColumnY * (Input.Block.y + Input.Block.w);
    }
#endif

    Result.Position = mul(u_Camera, float4(World, 1.0));

#ifdef ENABLE_BLOCK
    const float3 Toward = normalize(mul(u_CameraInverse, float4(0.0, 0.0, 1.0, 0.0)).xyz);
    const float3 BoxX   = Transform.ColumnX / max(dot(Transform.ColumnX, Transform.ColumnX), 1e-8);
    const float3 BoxY   = Transform.ColumnY / max(dot(Transform.ColumnY, Transform.ColumnY), 1e-8);
    const float3 BoxZ   = Transform.ColumnZ / max(dot(Transform.ColumnZ, Transform.ColumnZ), 1e-8);
    const float3 Rel    = World - ZyApplyAffine(Transform, Input.Block.xyz);
    float3       Dir    = float3(dot(Toward, BoxX), dot(Toward, BoxY), dot(Toward, BoxZ));

    // A line running along a face never crosses its slab, so it is nudged off the axis instead of dividing by nought.
    Dir = (abs(Dir) < 1e-5) ? float3(1e-5, 1e-5, 1e-5) : Dir;

    Result.Local   = float3(dot(Rel, BoxX), dot(Rel, BoxY), dot(Rel, BoxZ));
    Result.Inverse = 1.0 / Dir;
    Result.Half    = float3(Input.Girth.x * 0.5, Input.Block.w, Input.Girth.y * 0.5);
    Result.FaceX   = normalize(Transform.ColumnX) * -sign(Dir.x);
    Result.FaceY   = normalize(Transform.ColumnY) * -sign(Dir.y);
    Result.FaceZ   = normalize(Transform.ColumnZ) * -sign(Dir.z);
#endif

    // Art laid against the ground is coplanar with it, and would z-fight it without a nudge forward.
    if (Surface.Plane == kPlaneGround)
    {
        const float Along = u_ScreenX.w;

#ifdef ENABLE_RELIEF
        Result.Position.z -= u_Relief.y * Along;
#endif

        Result.Position.z -= kCoplanarLift * Along;
    }

    // Tiled art is read once per unit of its own size, so its frame is swept as many times as the transform stretches.
    const float2 Repeat = (Input.Orientation & kTiled) != 0u
        ? float2(length(Surface.AxisU), length(Surface.AxisV))
        : float2(1.0, 1.0);

    Result.Texture  = Input.Frame.xy + (Input.Frame.zw - Input.Frame.xy) * (ReadSample(Input.Orientation, Corner) * Repeat);
    Result.Color    = Input.Color;

#ifdef ENABLE_LAYERED
    Result.Layer = float(Input.Orientation >> kLayerShift);
#endif

#ifdef ENABLE_NORMAL_MAPPING
    // The map's right and up are the card's, which for art carrying the projection are the screen's.
    Result.AxisX = normalize(Surface.SpanU);
    Result.AxisY = normalize(Surface.SpanV);
#endif

    Result.AxisZ = normalize(Surface.Normal);

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

#ifdef ENABLE_LAYERED
Texture2DArray t_Albedo : register(t0);
#else
Texture2D      t_Albedo : register(t0);
#endif
SamplerState s_Albedo : register(s0);

#ifdef ENABLE_LAYERED
/// Reads a texel of the layer the instance names.
#define SpriteRead(Texture, Sampler, Coordinate, Layer) Texture.Sample(Sampler, float3(Coordinate, Layer))
#else
#define SpriteRead(Texture, Sampler, Coordinate, Layer) Texture.Sample(Sampler, Coordinate)
#endif

#ifdef ENABLE_NORMAL_MAPPING
#ifdef ENABLE_LAYERED
Texture2DArray t_Normal : register(t1);
#else
Texture2D      t_Normal : register(t1);
#endif
SamplerState s_Normal : register(s1);
#endif

#ifdef ENABLE_RELIEF
#ifdef ENABLE_LAYERED
Texture2DArray t_Relief : register(t2);
#else
Texture2D      t_Relief : register(t2);
#endif
SamplerState s_Relief : register(s2);

// Returns how far below the quad the greyscale sinks this texel, in world units.
float ReliefSink(float2 Texture, float Layer)
{
    return saturate(u_Relief.x - SpriteRead(t_Relief, s_Relief, Texture, Layer).r) * u_Relief.y;
}
#endif

#ifdef ENABLE_BLOCK

// Finds where the line of sight through this pixel first enters the box the art stands for.
bool EnterBlock(fs_Input Input, out float Along, out float3 Facing)
{
    const float3 T0   = (float3(-Input.Half.x, 0.0, -Input.Half.z) - Input.Local) * Input.Inverse;
    const float3 T1   = (float3( Input.Half.x, Input.Half.y, Input.Half.z) - Input.Local) * Input.Inverse;
    const float3 Near = min(T0, T1);
    const float3 Far  = max(T0, T1);

    const float Enter = max(Near.x, max(Near.y, Near.z));
    const float Leave = min(Far.x, min(Far.y, Far.z));

    Along  = 0.0;
    Facing = float3(0.0, 0.0, 0.0);

    if (Enter > Leave)
    {
        return false;
    }

    // The slab crossed last on the way in is the face the pixel lies on.
    Along  = Enter;
    Facing = (Near.x >= Near.y && Near.x >= Near.z) ? Input.FaceX : (Near.y >= Near.z) ? Input.FaceY : Input.FaceZ;

    return true;
}
#endif

#ifdef ENABLE_ALPHA_TEST

struct fs_Output
{
    float4 Albedo : SV_Target0;
    float4 Normal : SV_Target1;
#if defined(ENABLE_BLOCK)
    float  Depth  : SV_Depth;
#elif defined(ENABLE_RELIEF)
    float  Depth  : SV_DepthGreaterEqual;
#endif
};

fs_Output main(fs_Input Input)
{
    fs_Output Result;

#ifdef ENABLE_LAYERED
    const float Layer = Input.Layer;
#else
    const float Layer = 0.0;
#endif

    const float4 Texel = SpriteRead(t_Albedo, s_Albedo, Input.Texture, Layer);

    clip(Texel.a - 0.5);

#ifdef ENABLE_RELIEF
    const float Sink = ReliefSink(Input.Texture, Layer);
#else
    const float Sink = 0.0;
#endif

    Result.Albedo = float4(Input.Color.rgb * Texel.rgb, saturate(Sink / kReliefRange));

#ifdef ENABLE_NORMAL_MAPPING
    const float3 Tangent = normalize(ZyDecodeNormalMap(SpriteRead(t_Normal, s_Normal, Input.Texture, Layer).rgb));
    float3       Normal  = normalize(Tangent.x * Input.AxisX + Tangent.y * Input.AxisY + Tangent.z * Input.AxisZ);
#else
    float3       Normal  = Input.AxisZ;
#endif

#ifdef ENABLE_BLOCK
    float  Along;
    float3 Facing;

    if (EnterBlock(Input, Along, Facing))
    {
#ifndef ENABLE_NORMAL_MAPPING
        Normal = Facing;
#endif
        Result.Depth = Input.Position.z + Along * u_ScreenX.w;
    }
    else
    {
        Result.Depth = Input.Position.z;
    }
#endif

    // The two bits the normal buffer has left over carry nothing, so they are written full.
    Result.Normal = float4(ZyEncodeNormalMap(Normal), 1.0);

#if defined(ENABLE_RELIEF) && !defined(ENABLE_BLOCK)
    Result.Depth = Input.Position.z + Sink * u_ScreenX.w;
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

#ifdef ENABLE_LAYERED
    const float Layer = Input.Layer;
#else
    const float Layer = 0.0;
#endif

    Result.Color = Input.Color * SpriteRead(t_Albedo, s_Albedo, Input.Texture, Layer);

#ifdef ENABLE_RELIEF
    Result.Depth = Input.Position.z + ReliefSink(Input.Texture, Layer) * u_ScreenX.w;
#endif

    return Result;
}

#endif // ENABLE_ALPHA_TEST

#endif // FRAGMENT_SHADER