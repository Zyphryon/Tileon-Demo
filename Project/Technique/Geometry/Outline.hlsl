// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Resources://Technique/Common/Sprite.hlsl"

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Layout
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef ENABLE_LAYERED
Texture2DArray t_Albedo : register(t0);
#define OutlineRead(Input, Texture) t_Albedo.SampleLevel(s_Albedo, float3(Texture, Input.Layer), 0).a
#else
Texture2D      t_Albedo : register(t0);
#define OutlineRead(Input, Texture) t_Albedo.SampleLevel(s_Albedo, Texture, 0).a
#endif

SamplerState   s_Albedo : register(s0);

struct vs_Input
{
    uint   VertexID    : SV_VertexID;
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
    float4 Position : SV_POSITION;
    float2 Texture  : TEXCOORD0;
    float4 Color    : COLOR0;

    nointerpolation float  Stroke : TEXCOORD1;   // how many pixels of art the stroke stands out
    nointerpolation float4 Frame  : TEXCOORD3;   // the crop the art came from, which the stroke may not pass
#ifdef ENABLE_LAYERED
    nointerpolation float Layer  : TEXCOORD2;   // the layer of the material's array the art is read from
#endif
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(vs_Input Input)
{
    fs_Input Result;

    float2         Corner    = ZyEmitRect(Input.VertexID);
    const ZyAffine Transform = ZyReadAffine(Input.Transform0, Input.Transform1, Input.Transform2);
    const Face     Surface   = ReadFace(Input.Orientation, Transform);

    // The card is grown by the stroke it carries, since a ring standing outside the art needs room the art's
    // own crop does not have; the corners are pushed out from the middle, so the art stays where it stood.
#ifdef ENABLE_LAYERED
    float Spread, Height, Slices;
    t_Albedo.GetDimensions(Spread, Height, Slices);
#else
    float Spread, Height;
    t_Albedo.GetDimensions(Spread, Height);
#endif

    const float  Stroke = float((Input.Orientation >> kStrokeShift) & kStrokeMask);
    const float2 Crop   = abs(Input.Frame.zw - Input.Frame.xy) * float2(Spread, Height);
    const float2 Growth = (Crop + 2.0 * Stroke) / max(Crop, float2(1.0, 1.0));

    Corner = (Corner - 0.5) * Growth + 0.5;

    Result.Position = mul(u_Camera, float4(PlaceCorner(Transform, Surface, Corner, Input.Size), 1.0));

    // The stroke rings art that is already drawn, so it stands a hair nearer to keep off the seam it traces.
    Result.Position.z -= 0.02 * u_ScreenX.w;

    const float2 Repeat = (Input.Orientation & kTiled) != 0u
        ? float2(length(Surface.AxisU), length(Surface.AxisV))
        : float2(1.0, 1.0);

    Result.Texture = Input.Frame.xy
        + (Input.Frame.zw - Input.Frame.xy) * (ReadSample(Input.Orientation, Corner) * Repeat);
    Result.Color   = Input.Color;
    Result.Stroke  = float((Input.Orientation >> kStrokeShift) & kStrokeMask);
    Result.Frame   = Input.Frame;

#ifdef ENABLE_LAYERED
    Result.Layer   = float(Input.Orientation >> kLayerShift);
#endif

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

/// Reads how much of a point the art fills, counting anything past its own crop as empty.
float Coverage(fs_Input Input, float2 Texture)
{
    // A crop sits in an atlas beside art it knows nothing about, so a stroke that read past it would ring
    // whatever happened to be packed alongside.
    if (any(Texture < Input.Frame.xy) || any(Texture > Input.Frame.zw))
    {
        return 0.0;
    }
    return OutlineRead(Input, Texture);
}

float4 main(fs_Input Input) : SV_Target0
{
#ifdef ENABLE_LAYERED
    float Sheet, Tall, Slices;
    t_Albedo.GetDimensions(Sheet, Tall, Slices);
#else
    float Sheet, Tall;
    t_Albedo.GetDimensions(Sheet, Tall);
#endif

    const float2 Step   = float2(1.0 / Sheet, 1.0 / Tall);
    const float  Inside = Coverage(Input, Input.Texture);
    const int    Reach  = int(Input.Stroke);

    // The nearest art is what the ring is drawn from, and it is worth less the further out it was found, so
    // the band falls away toward its rim rather than ending on a step.
    float Strength = 0.0;

    [loop] for (int Index = 1; Index <= Reach; ++Index)
    {
        const float  Span = float(Index);
        const float  Fade = 1.0 - (Span - 1.0) / max(float(Reach), 1.0);
        const float2 Away = Step * Span;
        const float2 Bias = Away * 0.70710678;

        float Found = max(max(Coverage(Input, Input.Texture + float2( Away.x, 0.0)),
                              Coverage(Input, Input.Texture + float2(-Away.x, 0.0))),
                          max(Coverage(Input, Input.Texture + float2(0.0,  Away.y)),
                              Coverage(Input, Input.Texture + float2(0.0, -Away.y))));

        // The corners are asked as well, or the ring would come to a cross where the art turns.
        Found = max(Found, max(max(Coverage(Input, Input.Texture + float2( Bias.x,  Bias.y)),
                                   Coverage(Input, Input.Texture + float2(-Bias.x,  Bias.y))),
                               max(Coverage(Input, Input.Texture + float2( Bias.x, -Bias.y)),
                                   Coverage(Input, Input.Texture + float2(-Bias.x, -Bias.y)))));

        Strength = max(Strength, Found * Fade);
    }

    // What the art already fills is the art's, so the ring gives way as it meets it rather than cutting.
    const float Alpha = saturate(Strength) * (1.0 - Inside);

    clip(Alpha - 0.0001);

    return float4(Input.Color.rgb, Input.Color.a * Alpha);
}
#endif // FRAGMENT_SHADER