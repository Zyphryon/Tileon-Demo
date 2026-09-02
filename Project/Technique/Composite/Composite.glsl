// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Embedded://Shader/Color.glsl"
#include "Embedded://Shader/Noise.glsl"
#include "Embedded://Shader/Tonemap.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    vec4 u_Grading;   // X = Exposure, Y = Saturation, Z = Vignette, W = Grain
    vec4 u_Lift;      // RGB = Lift, W = Elapsed time
    vec4 u_Gamma;     // RGB = Gamma, W = The strength of the halo
    vec4 u_Gain;      // RGB = Gain, W = The levels each channel is stepped to
};

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

layout(binding = 0) uniform sampler2D t_Scene;

in vec2 v_Texture;

layout(location = 0) out vec4 out_Color;

layout(binding = 1) uniform sampler2D t_Bloom;

// GT7 is the curve the film is authored against; ACES is the variant a scene can ask for instead.
#if defined(ENABLE_TONEMAP_ACES)
    #define Tonemap ZyTonemapAces
#else
    #define Tonemap ZyTonemapGt
#endif // ENABLE_TONEMAP_ACES

float Grain(vec2 Pixel, uint Frame)
{
    ivec2 Cell = ivec2(Pixel);
    uint  Seed = ZyScatter(uint(Cell.x) * 73856093u ^ uint(Cell.y) * 19349663u ^ Frame * 83492791u);

    return float(Seed & 0xFFFFu) * (1.0 / 65535.0) - 0.5;
}

// A 4x4 ordered matrix, which is what leaves a stepped gradient dithered rather than banded.
const float kBayer[16] = float[16](
     0.0 / 16.0,  8.0 / 16.0,  2.0 / 16.0, 10.0 / 16.0,
    12.0 / 16.0,  4.0 / 16.0, 14.0 / 16.0,  6.0 / 16.0,
     3.0 / 16.0, 11.0 / 16.0,  1.0 / 16.0,  9.0 / 16.0,
    15.0 / 16.0,  7.0 / 16.0, 13.0 / 16.0,  5.0 / 16.0
);

vec3 Palette(vec3 Color, float Levels, vec2 Pixel)
{
    ivec2 Cell  = ivec2(Pixel) & 3;
    float Steps = Levels - 1.0;

    return floor(Color * Steps + 0.5 + (kBayer[Cell.y * 4 + Cell.x] - 0.5)) / Steps;
}

void main()
{
    // The lights already shaded what they landed on, so the scene target holds scene color.
    vec3 Scene = texture(t_Scene, v_Texture).rgb;

    // Exposure moves the scene into the knee, and the curve is what brings it into display range.
    // The halo is scene referred, so it joins the scene before exposure carries the pair into the curve.
    vec3 Lit = Scene;

    if (u_Gamma.w > 0.0)
    {
        Lit += texture(t_Bloom, v_Texture).rgb * u_Gamma.w;
    }

    vec3 Color = Tonemap(Lit * u_Grading.x);

    // The bands are graded on the image the curve handed back, which is the range they are authored against.
    Color = pow(max(Color * u_Gain.rgb + u_Lift.rgb, vec3(0.0)), u_Gamma.rgb);

    // Rec. 709 luma, so dropping the color leaves the brightness the eye already read.
    float Luma = ZyLuminance(Color);
    Color = mix(vec3(Luma), Color, u_Grading.y);

    // The corners fall off with the square of the distance out from the middle.
    vec2 Offset = v_Texture - 0.5;
    Color *= 1.0 - u_Grading.z * clamp(dot(Offset, Offset) * 2.0, 0.0, 1.0);

    // Silver shows most where the exposure landed halfway, and falls away towards an unexposed black
    // and a saturated white alike. The luma is read after the vignette, so a darkened corner grains less.
    float Exposed = ZyLuminance(Color);
    float Density = sqrt(clamp(4.0 * Exposed * (1.0 - Exposed), 0.0, 1.0));

    Color += Grain(gl_FragCoord.xy, uint(u_Lift.w * 24.0)) * (u_Grading.w * Density);

    Color = clamp(Color, 0.0, 1.0);

    // The palette is what the display carried, so the steps land last, over the grain that dithers them.
    if (u_Gain.w > 1.0)
    {
        Color = Palette(Color, u_Gain.w, gl_FragCoord.xy);
    }

    out_Color = vec4(Color, 1.0);
}

#endif // FRAGMENT_SHADER