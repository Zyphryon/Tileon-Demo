// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"

layout(std140, binding = 1) uniform cb_Pass
{
    mat4 u_Sunlight;    // Turns world space into the sun's own clip space.
    vec4 u_Toward;      // The direction the sun stands in, of unit length, with w unused.
};

const float kCardCutoff = 0.35;
const float kCardLift   = 0.15;

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

layout(location = 0) in vec4 a_Center;    // the anchor the art stands on, with w unused
layout(location = 1) in vec4 a_Size;      // how wide and tall the art stands, with zw unused
layout(location = 2) in vec4 a_Frame;     // the art's crop within the sheet it is packed in

out vec2  v_Texture;
out float v_Along;   // how far along the sun the card stands, over the map's own span

void main()
{
    vec2 Corner = ZyEmitRect(gl_VertexID);
    vec3 Toward = u_Toward.xyz;

    vec3 Leaning = vec3(0.0, 1.0, 0.0) - Toward * Toward.y;
    vec3 Raised  = (dot(Leaning, Leaning) > 1e-6) ? normalize(Leaning) : vec3(0.0, 0.0, 1.0);
    vec3 Right   = normalize(cross(Toward, Raised));
    vec3 Footing = a_Center.xyz + vec3(0.0, a_Size.y * kCardLift, 0.0);

    vec3 Position = Footing
                  + Right  * ((Corner.x - 0.5) * a_Size.x)
                  + Raised * (Corner.y * a_Size.y);

    vec4 Clip = u_Sunlight * vec4(Position, 1.0);

    gl_Position = Clip;
    v_Along     = Clip.z;
    v_Texture   = mix(a_Frame.xy, a_Frame.zw, vec2(Corner.x, 1.0 - Corner.y));
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

layout(binding = 0) uniform sampler2D t_Albedo;

in vec2  v_Texture;
in float v_Along;

layout(location = 0) out float out_Along;

void main()
{
    if (texture(t_Albedo, v_Texture).a < kCardCutoff)
    {
        discard;
    }

    out_Along = clamp(v_Along, 0.0, 1.0);
}

#endif // FRAGMENT_SHADER
