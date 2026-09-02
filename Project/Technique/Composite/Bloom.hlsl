// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Embedded://Shader/Math.hlsl"

cbuffer cb_Pass : register(b1)
{
    float4 u_Filter;    // X = Threshold, Y = Knee, ZW = The step from one tap to the next
};

static const float kWeight[5] = {  0.070270,  0.316216, 0.227027, 0.316216, 0.070270 };
static const float kOffset[5] = { -3.230769, -1.384615, 0.000000, 1.384615, 3.230769 };

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

float3 Extract(float3 Color)
{
    const float Peak = ZyMax3(Color.r, Color.g, Color.b);
    const float Soft = clamp(Peak - u_Filter.x + u_Filter.y, 0.0, 2.0 * u_Filter.y);
    const float Gain = max(Peak - u_Filter.x, Soft * Soft / (4.0 * u_Filter.y + 0.0001));

    return Color * (Gain / max(Peak, 0.0001));
}

float4 main(fs_Input Input) : SV_Target
{
    float3 Result = float3(0.0, 0.0, 0.0);

    for (int Y = 0; Y < 5; ++Y)
    {
        for (int X = 0; X < 5; ++X)
        {
            const float2 Offset = float2(kOffset[X], kOffset[Y]) * u_Filter.zw;

            Result += Extract(t_Scene.Sample(s_Scene, Input.Texture + Offset).rgb) * (kWeight[X] * kWeight[Y]);
        }
    }

    return float4(Result, 1.0);
}

#endif // FRAGMENT_SHADER