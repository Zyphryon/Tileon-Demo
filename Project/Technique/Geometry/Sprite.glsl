// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#extension GL_ARB_conservative_depth : enable

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

#ifdef ENABLE_BLOCK
layout(location = 7) in vec4 a_Block;    // where the box rises from, in the sprite's own units, and how high it reaches
layout(location = 8) in vec2 a_Girth;    // how wide and how deep the box runs, in the sprite's own units
#endif

out vec2 v_Texture;
out vec4 v_Color;

#ifdef ENABLE_LAYERED
flat out float v_Layer;     // the layer of the material's array the art is read from
#endif

#ifdef ENABLE_NORMAL_MAPPING
out vec3 v_AxisX;
out vec3 v_AxisY;
#endif
out vec3 v_AxisZ;

#ifdef ENABLE_BLOCK
out vec3      v_Local;      // the point of the card this corner stands at, in the box's own frame
flat out vec3 v_Inverse;    // the reciprocal of the line of sight in that frame, which turns each slab's divide into a multiply
flat out vec3 v_Half;       // half the width, the whole height, and half the depth of the box
flat out vec3 v_FaceX;      // each face's normal, already turned against the line of sight
flat out vec3 v_FaceY;
flat out vec3 v_FaceZ;
#endif

void main()
{
    vec2     Corner    = ZyEmitRect(gl_VertexID);
    ZyAffine Transform = ZyReadAffine(a_Transform0, a_Transform1, a_Transform2);
    Face     Surface   = ReadFace(a_Orientation, Transform);

    vec3 World = PlaceCorner(Transform, Surface, Corner, a_Size);

#ifdef ENABLE_BLOCK
    // An edge-on run's art is the top of its box, so its card lies on the box rather than on the ground: a segment
    // then draws its own top to its very end, and the front of the segment beyond is never seen through the seam.
    if (Surface.Edge)
    {
        World += Transform.ColumnY * (a_Block.y + a_Block.w);
    }
#endif

    gl_Position = u_Camera * vec4(World, 1.0);

#ifdef ENABLE_BLOCK
    vec3 Toward = normalize((u_CameraInverse * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
    vec3 BoxX   = Transform.ColumnX / max(dot(Transform.ColumnX, Transform.ColumnX), 1e-8);
    vec3 BoxY   = Transform.ColumnY / max(dot(Transform.ColumnY, Transform.ColumnY), 1e-8);
    vec3 BoxZ   = Transform.ColumnZ / max(dot(Transform.ColumnZ, Transform.ColumnZ), 1e-8);
    vec3 Rel    = World - ZyApplyAffine(Transform, a_Block.xyz);
    vec3 Dir    = vec3(dot(Toward, BoxX), dot(Toward, BoxY), dot(Toward, BoxZ));

    // A line running along a face never crosses its slab, so it is nudged off the axis instead of dividing by nought.
    Dir = mix(Dir, vec3(1e-5), lessThan(abs(Dir), vec3(1e-5)));

    v_Local   = vec3(dot(Rel, BoxX), dot(Rel, BoxY), dot(Rel, BoxZ));
    v_Inverse = 1.0 / Dir;
    v_Half    = vec3(a_Girth.x * 0.5, a_Block.w, a_Girth.y * 0.5);
    v_FaceX   = normalize(Transform.ColumnX) * -sign(Dir.x);
    v_FaceY   = normalize(Transform.ColumnY) * -sign(Dir.y);
    v_FaceZ   = normalize(Transform.ColumnZ) * -sign(Dir.z);
#endif

    // Art laid against the ground is coplanar with it, and would z-fight it without a nudge forward.
    if (Surface.Plane == kPlaneGround)
    {
        float Along = u_ScreenX.w;

#ifdef ENABLE_RELIEF
        gl_Position.z -= u_Relief.y * Along;
#endif

        gl_Position.z -= kCoplanarLift * Along;
    }

    // Tiled art is read once per unit of its own size, so its frame is swept as many times as the transform stretches.
    vec2 Repeat = (a_Orientation & kTiled) != 0u
        ? vec2(length(Surface.AxisU), length(Surface.AxisV))
        : vec2(1.0);

    v_Texture = a_Frame.xy + (a_Frame.zw - a_Frame.xy) * (ReadSample(a_Orientation, Corner) * Repeat);
    v_Color   = a_Color;

#ifdef ENABLE_LAYERED
    v_Layer = float(a_Orientation >> kLayerShift);
#endif

#ifdef ENABLE_NORMAL_MAPPING
    // The map's right and up are the card's, which for art carrying the projection are the screen's.
    v_AxisX = normalize(Surface.SpanU);
    v_AxisY = normalize(Surface.SpanV);
#endif

    v_AxisZ = normalize(Surface.Normal);
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

#ifdef ENABLE_LAYERED
layout(binding = 0) uniform sampler2DArray t_Albedo;
#else
layout(binding = 0) uniform sampler2D      t_Albedo;
#endif

#ifdef ENABLE_NORMAL_MAPPING
#ifdef ENABLE_LAYERED
layout(binding = 1) uniform sampler2DArray t_Normal;
#else
layout(binding = 1) uniform sampler2D      t_Normal;
#endif
#endif

in vec2 v_Texture;
in vec4 v_Color;

#ifdef ENABLE_LAYERED
flat in float v_Layer;

/// Reads a texel of the layer the instance names.
#define SpriteRead(Sampler, Texture) texture(Sampler, vec3(Texture, v_Layer))
#else
#define SpriteRead(Sampler, Texture) texture(Sampler, Texture)
#endif

#ifdef ENABLE_NORMAL_MAPPING
in vec3 v_AxisX;
in vec3 v_AxisY;
#endif
in vec3 v_AxisZ;

#ifdef ENABLE_RELIEF
#ifdef ENABLE_LAYERED
layout(binding = 2) uniform sampler2DArray t_Relief;
#else
layout(binding = 2) uniform sampler2D      t_Relief;
#endif

#if defined(GL_ARB_conservative_depth) && !defined(ENABLE_BLOCK)
layout(depth_greater) out float gl_FragDepth;
#endif

// Returns how far below the quad the greyscale sinks this texel, in world units.
float ReliefSink(vec2 Texture)
{
    return clamp(u_Relief.x - SpriteRead(t_Relief, Texture).r, 0.0, 1.0) * u_Relief.y;
}
#endif

#ifdef ENABLE_BLOCK
in vec3      v_Local;
flat in vec3 v_Inverse;
flat in vec3 v_Half;
flat in vec3 v_FaceX;
flat in vec3 v_FaceY;
flat in vec3 v_FaceZ;

/// Finds where the line of sight through this pixel first enters the box the art stands for.
bool EnterBlock(out float Along, out vec3 Facing)
{
    vec3 T0   = (vec3(-v_Half.x, 0.0, -v_Half.z) - v_Local) * v_Inverse;
    vec3 T1   = (vec3( v_Half.x, v_Half.y, v_Half.z) - v_Local) * v_Inverse;
    vec3 Near = min(T0, T1);
    vec3 Far  = max(T0, T1);

    float Enter = max(Near.x, max(Near.y, Near.z));
    float Leave = min(Far.x, min(Far.y, Far.z));

    if (Enter > Leave)
    {
        return false;
    }

    // The slab crossed last on the way in is the face the pixel lies on.
    Along  = Enter;
    Facing = (Near.x >= Near.y && Near.x >= Near.z) ? v_FaceX : (Near.y >= Near.z) ? v_FaceY : v_FaceZ;

    return true;
}
#endif

#ifdef ENABLE_ALPHA_TEST

layout(location = 0) out vec4 out_Albedo;
layout(location = 1) out vec4 out_Normal;

void main()
{
    vec4 Texel = SpriteRead(t_Albedo, v_Texture);

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
    vec3 Tangent = normalize(ZyDecodeNormalMap(SpriteRead(t_Normal, v_Texture).rgb));
    vec3 Normal  = normalize(Tangent.x * v_AxisX + Tangent.y * v_AxisY + Tangent.z * v_AxisZ);
#else
    vec3 Normal  = v_AxisZ;
#endif

#ifdef ENABLE_BLOCK
    float Along;
    vec3  Facing;

    if (EnterBlock(Along, Facing))
    {
#ifndef ENABLE_NORMAL_MAPPING
        Normal = Facing;
#endif
        gl_FragDepth = gl_FragCoord.z + Along * u_ScreenX.w;
    }
    else
    {
        gl_FragDepth = gl_FragCoord.z;
    }
#endif

    // The two bits the normal buffer has left over carry nothing, so they are written full.
    out_Normal = vec4(ZyEncodeNormalMap(Normal), 1.0);

#if defined(ENABLE_RELIEF) && !defined(ENABLE_BLOCK)
    gl_FragDepth = gl_FragCoord.z + Sink * u_ScreenX.w;
#endif
}

#else

layout(location = 0) out vec4 out_Albedo;

// Transparent sprites blend into the lit scene, so they write one target and take no lighting.
void main()
{
    out_Albedo = v_Color * SpriteRead(t_Albedo, v_Texture);

#ifdef ENABLE_RELIEF
    gl_FragDepth = gl_FragCoord.z + ReliefSink(v_Texture) * u_ScreenX.w;
#endif
}

#endif // ENABLE_ALPHA_TEST

#endif // FRAGMENT_SHADER