// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Embedded://Shader/Packing.glsl"
#include "Embedded://Shader/Depth.glsl"
#include "Resources://Technique/Common/Scene.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    vec4 u_SunColor;      // RGB = Color * Intensity * Headroom, A = Sun Direction X
    vec4 u_SkyColor;      // RGB = Color * Intensity * Headroom, A = Sun Direction Y
    vec4 u_GroundColor;   // RGB = Color * Intensity * Headroom, A = Sun Direction Z
    mat4 u_Sunlight;      // Turns world space into the sun's clip space, which its map is read through
    vec4 u_Sunstep;       // XY = what one texel of that map covers, ZW unused
};

/// How far a surface is let off the map before it is taken to be standing in its own shadow.
const float kSunBias = 0.0015;

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

out vec2 v_Probe;    // the point on the near plane this pixel looks along

void main()
{
    vec2 Clip = ZyEmitScreen(gl_VertexID).xy;

    gl_Position = vec4(Clip, 0.0, 1.0);
    v_Probe     = Clip;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

layout(binding = 0) uniform sampler2D t_Normal;
layout(binding = 1) uniform sampler2D t_Albedo;
layout(binding = 2) uniform sampler2D t_Depth;
layout(binding = 3) uniform sampler2D t_Sunlight;

in vec2 v_Probe;

layout(location = 0) out vec3 out_Color;

float Sunlit(vec3 World)
{
    vec4 Lit = u_Sunlight * vec4(World, 1.0);

    // GL reads a target from its lower left, so the flip the HLSL twin needs is exactly what is left out here.
    vec2 Map = Lit.xy * 0.5 + 0.5;

    if (any(lessThan(Map, vec2(0.0))) || any(greaterThan(Map, vec2(1.0))) || Lit.z < 0.0 || Lit.z > 1.0)
    {
        return 1.0;
    }

    float Depth = Lit.z - kSunBias;
    float Sum   = 0.0;

    for (int Y = -1; Y <= 1; ++Y)
    {
        for (int X = -1; X <= 1; ++X)
        {
            vec2 Tap = Map + vec2(X, Y) * u_Sunstep.xy;

            Sum += (Depth <= textureLod(t_Sunlight, Tap, 0.0).r) ? 1.0 : 0.0;
        }
    }
    return Sum * (1.0 / 9.0);
}

void main()
{
    ivec2 Texel  = ivec2(gl_FragCoord.xy);
    vec4  Base   = texelFetch(t_Albedo, Texel, 0);
    vec3  Albedo = Base.rgb;
    vec3  Normal = normalize(ZyDecodeNormalMap(texelFetch(t_Normal, Texel, 0).rgb));

    // The same reading the local lights take, so both agree on where a pixel actually stands.
    float Sorted = texelFetch(t_Depth, Texel, 0).r;
    float Depth  = Sorted - Base.a * kReliefRange / ZyDepthSpan(u_CameraInverse);
    vec4  Probe  = u_CameraInverse * vec4(v_Probe, ZyClipDepth(Depth), 1.0);
    vec3  World  = Probe.xyz / Probe.w;

    // Hemisphere ambient. The weight is world Y, so this reads as "facing the sky" only because the normal
    // buffer stores world-space normals with Y up.
    float Weight  = Normal.y * 0.5 + 0.5;
    vec3  Ambient = mix(u_GroundColor.rgb, u_SkyColor.rgb, Weight);
    vec3  Toward  = vec3(u_SunColor.w, u_SkyColor.w, u_GroundColor.w);
    vec3  Sun     = u_SunColor.rgb * max(dot(Normal, Toward), 0.0) * Sunlit(World);

    // Every light shades the surface it lands on, so the radiance target holds scene color and the composite
    // only tone maps it. Summing the lights and multiplying once at the end is the same math.
    out_Color = Albedo * (Ambient + Sun);
}

#endif // FRAGMENT_SHADER