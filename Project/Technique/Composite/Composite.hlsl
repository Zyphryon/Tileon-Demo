// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Embedded://Shader/Color.hlsl"
#include "Embedded://Shader/Noise.hlsl"
#include "Embedded://Shader/Tonemap.hlsl"

cbuffer cb_Pass : register(b1)
{
    float4 u_Grading;   // X = Exposure, Y = Saturation, Z = Vignette, W = Grain
    float4 u_Lift;      // RGB = Lift, W = Elapsed time
    float4 u_Gamma;     // RGB = Gamma, W = The strength of the halo
    float4 u_Gain;      // RGB = Gain, W = The levels each channel is stepped to
};

struct fs_Input
{
    float4 Position : SV_POSITION;
    float2 Texture  : TEXCOORD0;
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(uint VertexID : SV_VertexID)
{
    const float4 Screen = ZyEmitScreen(VertexID);

    fs_Input Result;

    Result.Position = float4(Screen.xy, 0.0, 1.0);
    Result.Texture  = Screen.zw;

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

Texture2D    t_Scene : register(t0);
SamplerState s_Scene : register(s0);

Texture2D    t_Bloom : register(t1);
SamplerState s_Bloom : register(s1);

// GT7 is the curve the film is authored against; ACES is the variant a scene can ask for instead.
#if defined(ENABLE_TONEMAP_ACES)
    #define Tonemap ZyTonemapAces
#else
    #define Tonemap ZyTonemapGt
#endif // ENABLE_TONEMAP_ACES

float Grain(float2 Pixel, uint Frame)
{
    const int2 Cell = int2(Pixel);
    const uint Seed = ZyScatter(uint(Cell.x) * 73856093u ^ uint(Cell.y) * 19349663u ^ Frame * 83492791u);

    return float(Seed & 0xFFFFu) * (1.0 / 65535.0) - 0.5;
}

// A 4x4 ordered matrix, which is what leaves a stepped gradient dithered rather than banded.
static const float kBayer[16] =
{
     0.0 / 16.0,  8.0 / 16.0,  2.0 / 16.0, 10.0 / 16.0,
    12.0 / 16.0,  4.0 / 16.0, 14.0 / 16.0,  6.0 / 16.0,
     3.0 / 16.0, 11.0 / 16.0,  1.0 / 16.0,  9.0 / 16.0,
    15.0 / 16.0,  7.0 / 16.0, 13.0 / 16.0,  5.0 / 16.0,
};

float3 Palette(float3 Color, float Levels, float2 Pixel)
{
    const int2  Cell  = int2(Pixel) & 3;
    const float Steps = Levels - 1.0;

    return floor(Color * Steps + 0.5 + (kBayer[Cell.y * 4 + Cell.x] - 0.5)) / Steps;
}

float4 main(fs_Input Input) : SV_Target
{
    // The lights already shaded what they landed on, so the scene target holds scene color.
    const float3 Scene = t_Scene.Sample(s_Scene, Input.Texture).rgb;

    // Exposure moves the scene into the knee, and the curve is what brings it into display range.
    // The halo is scene referred, so it joins the scene before exposure carries the pair into the curve.
    float3 Lit = Scene;

    if (u_Gamma.w > 0.0)
    {
        Lit += t_Bloom.Sample(s_Bloom, Input.Texture).rgb * u_Gamma.w;
    }

    float3 Color = Tonemap(Lit * u_Grading.x);

    // The bands are graded on the image the curve handed back, which is the range they are authored against.
    Color = pow(max(Color * u_Gain.rgb + u_Lift.rgb, 0.0), u_Gamma.rgb);

    // Rec. 709 luma, so dropping the color leaves the brightness the eye already read.
    const float Luma = ZyLuminance(Color);
    Color = lerp(float3(Luma, Luma, Luma), Color, u_Grading.y);

    // The corners fall off with the square of the distance out from the middle.
    const float2 Offset = Input.Texture - 0.5;
    Color *= 1.0 - u_Grading.z * saturate(dot(Offset, Offset) * 2.0);

    // Silver shows most where the exposure landed halfway, and falls away towards an unexposed black
    // and a saturated white alike. The luma is read after the vignette, so a darkened corner grains less.
    const float Exposed = ZyLuminance(Color);
    const float Density = sqrt(saturate(4.0 * Exposed * (1.0 - Exposed)));

    Color += Grain(Input.Position.xy, uint(u_Lift.w * 24.0)) * (u_Grading.w * Density);

    Color = saturate(Color);

    // The palette is what the display carried, so the steps land last, over the grain that dithers them.
    if (u_Gain.w > 1.0)
    {
        Color = Palette(Color, u_Gain.w, Input.Position.xy);
    }

    return float4(Color, 1.0);
}

#endif // FRAGMENT_SHADER