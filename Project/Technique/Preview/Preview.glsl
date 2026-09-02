// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Embedded://Shader/Color.glsl"
#include "Embedded://Shader/Depth.glsl"
#include "Resources://Technique/Common/Scene.glsl"

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

out vec2 v_Texture;
out vec2 v_Probe;     // the pixel's clip-space coordinates

void main()
{
    vec4 Screen = ZyEmitScreen(gl_VertexID);

    gl_Position = vec4(Screen.xy, 0.0, 1.0);
    v_Texture   = Screen.zw;
    v_Probe     = Screen.xy;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

layout(binding = 0) uniform sampler2D t_Source;

in vec2 v_Texture;
in vec2 v_Probe;

layout(location = 0) out vec4 out_Color;

void main()
{
#if defined(PREVIEW_NORMAL)

    out_Color = vec4(ZyToGamma(texture(t_Source, v_Texture).rgb), 1.0);

#elif defined(PREVIEW_DEPTH)

    float Depth     = texture(t_Source, v_Texture).r;
    vec4  Probe     = u_CameraInverse * vec4(v_Probe, ZyClipDepth(Depth), 1.0);
    float Elevation = clamp((Probe.y / Probe.w) / ELEVATION_SCALE, 0.0, 1.0);

    vec3 Color = mix(vec3(0.12), vec3(1.0), Elevation);

    out_Color = vec4(ZyToGamma(Color * step(Depth, 0.99999)), 1.0);

#else

    vec3 Scene = texture(t_Source, v_Texture).rgb;

#ifdef    PREVIEW_GAMMA
    Scene = ZyToGamma(Scene);
#endif // PREVIEW_GAMMA

    out_Color = vec4(Scene, 1.0);

#endif
}

#endif // FRAGMENT_SHADER