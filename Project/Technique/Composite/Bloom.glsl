// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Embedded://Shader/Math.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    vec4 u_Filter;    // X = Threshold, Y = Knee, ZW = The step from one tap to the next
};

const float kWeight[5] = float[5]( 0.070270,  0.316216, 0.227027, 0.316216, 0.070270);
const float kOffset[5] = float[5](-3.230769, -1.384615, 0.000000, 1.384615, 3.230769);

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

out vec2 v_Texture;

void main()
{
    vec4 Screen = ZyEmitScreen(gl_VertexID);

    gl_Position = vec4(Screen.xy, 0.0, 1.0);
    v_Texture   = Screen.zw;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

uniform sampler2D t_Scene;

in vec2 v_Texture;

layout(location = 0) out vec4 out_Color;

vec3 Extract(vec3 Color)
{
    float Peak = ZyMax3(Color.r, Color.g, Color.b);
    float Soft = clamp(Peak - u_Filter.x + u_Filter.y, 0.0, 2.0 * u_Filter.y);
    float Gain = max(Peak - u_Filter.x, Soft * Soft / (4.0 * u_Filter.y + 0.0001));

    return Color * (Gain / max(Peak, 0.0001));
}

void main()
{
    vec3 Result = vec3(0.0);

    for (int Y = 0; Y < 5; ++Y)
    {
        for (int X = 0; X < 5; ++X)
        {
            vec2 Offset = vec2(kOffset[X], kOffset[Y]) * u_Filter.zw;

            Result += Extract(texture(t_Scene, v_Texture + Offset).rgb) * (kWeight[X] * kWeight[Y]);
        }
    }

    out_Color = vec4(Result, 1.0);
}

#endif // FRAGMENT_SHADER