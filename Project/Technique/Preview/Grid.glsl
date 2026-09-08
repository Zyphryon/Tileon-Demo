// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Embedded://Shader/Grid.glsl"
#include "Resources://Technique/Common/Scene.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    vec2 u_Dimension;
};

const vec4 kColorTiles   = vec4(1.00, 1.00, 1.00, 0.10);
const vec4 kColorRegions = vec4(0.100482, 0.522522, 1.000000, 0.60);

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

out vec2 v_World;

void main()
{
    gl_Position = vec4(ZyEmitScreen(gl_VertexID).xy, 0.0, 1.0);

    vec4 Head = u_CameraInverse * vec4(gl_Position.xy, 0.0, 1.0);
    vec4 Tail = u_CameraInverse * vec4(gl_Position.xy, 1.0, 1.0);

    vec3 Origin    = Head.xyz / Head.w;
    vec3 Direction = Tail.xyz / Tail.w - Origin;

    v_World = (Origin - Direction * (Origin.y / Direction.y)).xz;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

in vec2 v_World;

layout(location = 0) out vec4 out_Color;

void main()
{
    float Tile   = ZyGridLine(v_World);
    float Region = ZyGridLine(v_World / u_Dimension);

    vec4 Result  = mix(
        vec4(kColorTiles.rgb,   kColorTiles.a   * Tile),
        vec4(kColorRegions.rgb, kColorRegions.a * Region), Region);

    if (Result.a < 0.001)
    {
        discard;
    }
    out_Color = Result;
}

#endif // FRAGMENT_SHADER