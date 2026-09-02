// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Embedded://Shader/Depth.glsl"
#include "Embedded://Shader/Packing.glsl"
#include "Resources://Technique/Common/Sprite.glsl"

const float kCoplanarLift = 0.01;

#ifdef ENABLE_RELIEF
layout(std140, binding = 2) uniform cb_Material
{
    vec2 u_Relief;    // X = The level the greyscale calls the quad, Y = How far below it reaches, in world units
};
#endif

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

layout(location = 0) in vec4 a_Transform0;
layout(location = 1) in vec4 a_Transform1;
layout(location = 2) in vec4 a_Transform2;

layout(location = 3) in vec4 a_Frame;
layout(location = 4) in vec2 a_Size;
layout(location = 5) in vec4 a_Color;
layout(location = 6) in uint a_Orientation;

out vec2 v_Texture;
out vec4 v_Color;

#ifdef ENABLE_NORMAL_MAPPING
out vec3 v_AxisX;
out vec3 v_AxisY;
#endif
out vec3 v_AxisZ;

void main()
{
    vec2   Corner    = ZyEmitRect(gl_VertexID);
    Affine Transform = ReadAffine(a_Transform0, a_Transform1, a_Transform2);
    Face   Surface    = ReadFace(a_Orientation, Transform);

    gl_Position = u_Camera * vec4(PlaceCorner(Transform, Surface, Corner, a_Size), 1.0);

    // Art laid against the ground is coplanar with it, and would z-fight it without a nudge forward.
    if (Surface.Plane == kPlaneGround)
    {
        float Along = ZyDepthSpan(u_CameraInverse);

#ifdef ENABLE_RELIEF
        gl_Position.z -= u_Relief.y / Along;
#endif

        gl_Position.z -= kCoplanarLift / Along;
    }

    v_Texture = mix(a_Frame.xy, a_Frame.zw, ReadSample(a_Orientation, Corner));
    v_Color   = a_Color;

#ifdef ENABLE_NORMAL_MAPPING
    v_AxisX = normalize(Surface.AxisU);
    v_AxisY = normalize(Surface.AxisV);
#endif

    v_AxisZ = normalize(Surface.Normal);
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

uniform sampler2D t_Albedo;

#ifdef ENABLE_NORMAL_MAPPING
uniform sampler2D t_Normal;
#endif

in vec2 v_Texture;
in vec4 v_Color;

#ifdef ENABLE_NORMAL_MAPPING
in vec3 v_AxisX;
in vec3 v_AxisY;
#endif
in vec3 v_AxisZ;

#ifdef ENABLE_RELIEF
uniform sampler2D t_Relief;

// Returns how far below the quad the greyscale sinks this texel, in world units.
float ReliefSink(vec2 Texture)
{
    return clamp(u_Relief.x - texture(t_Relief, Texture).r, 0.0, 1.0) * u_Relief.y;
}
#endif

#ifdef ENABLE_ALPHA_TEST

layout(location = 0) out vec4 out_Albedo;
layout(location = 1) out vec4 out_Normal;

void main()
{
    vec4 Texel = texture(t_Albedo, v_Texture);

    if (Texel.a < 0.5)
    {
        discard;
    }

#ifdef ENABLE_RELIEF
    float Sink = ReliefSink(v_Texture);
#else
    float Sink = 0.0;
#endif

    out_Albedo = vec4(v_Color.rgb * Texel.rgb, clamp(Sink / kReliefRange, 0.0, 1.0));

#ifdef ENABLE_NORMAL_MAPPING
    vec3 Tangent = normalize(ZyDecodeNormalMap(texture(t_Normal, v_Texture).rgb));
    vec3 Normal  = normalize(Tangent.x * v_AxisX + Tangent.y * v_AxisY + Tangent.z * v_AxisZ);
#else
    vec3 Normal  = v_AxisZ;
#endif

    // The two bits the normal buffer has left over carry nothing, so they are written full.
    out_Normal = vec4(ZyEncodeNormalMap(Normal), 1.0);

#ifdef ENABLE_RELIEF
    gl_FragDepth = gl_FragCoord.z + Sink / ZyDepthSpan(u_CameraInverse);
#endif
}

#else

layout(location = 0) out vec4 out_Albedo;

// Transparent sprites blend into the lit scene, so they write one target and take no lighting.
void main()
{
    out_Albedo = v_Color * texture(t_Albedo, v_Texture);

#ifdef ENABLE_RELIEF
    gl_FragDepth = gl_FragCoord.z + ReliefSink(v_Texture) / ZyDepthSpan(u_CameraInverse);
#endif
}

#endif // ENABLE_ALPHA_TEST

#endif // FRAGMENT_SHADER