// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Resources://Technique/Common/Scene.glsl"

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

layout(location = 0) in vec3 a_Center;
layout(location = 1) in vec3 a_Extent;
layout(location = 2) in vec4 a_Tint;

out vec4 v_Tint;

void main()
{
#ifdef BOUNDARY_FLAT

    // A flat boundary is the screen rectangle the volume covers, so it is bounded in clip space instead.
    vec4 Origin = u_Camera * vec4(a_Center, 1.0);
    vec2 Span   = abs((u_Camera * vec4(a_Extent.x, 0.0, 0.0, 0.0)).xy)
                + abs((u_Camera * vec4(0.0, a_Extent.y, 0.0, 0.0)).xy)
                + abs((u_Camera * vec4(0.0, 0.0, a_Extent.z, 0.0)).xy);

    gl_Position = vec4(Origin.xy + ZyEmitQuadEdges(gl_VertexID) * Span, Origin.z, Origin.w);

#else

    gl_Position = u_Camera * vec4(a_Center + ZyEmitBox(gl_VertexID) * a_Extent, 1.0);

#endif // BOUNDARY_FLAT

    v_Tint = a_Tint;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

in vec4 v_Tint;

layout(location = 0) out vec4 out_Color;

void main()
{
    out_Color = v_Tint;
}

#endif // FRAGMENT_SHADER