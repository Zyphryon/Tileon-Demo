// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.glsl"
#include "Embedded://Shader/Depth.glsl"
#include "Embedded://Shader/Noise.glsl"
#include "Embedded://Shader/Packing.glsl"
#include "Resources://Technique/Common/Scene.glsl"
#include "Resources://Technique/Common/Shadow.glsl"

const float kDitherScale     = 128.0;

const int   kShadowSearch    = 8;
const int   kShadowTaps      = 16;
const float kShadowSource    = 0.05;
const float kShadowSpread    = 0.06;
const float kShadowMinimum   = 0.004;
const float kShadowFacing    = 0.3;
const float kShadowSlope     = 0.03;
const float kShadowBias      = 0.004;
const float kShadowLift      = 0.25;

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

in vec4 a_Params0;    // center.xyz, radius || range

#if defined(LIGHT_SPOT)
in vec4 a_Params1;    // direction.xyz, cos(inner)
#endif

in vec4 a_Color;      // rgb, falloff
in float a_Slot;       // band of the shadow atlas, or -1 when the light casts none

#if defined(LIGHT_SPOT)
in float a_Outer;      // cos(outer)
#endif

out vec4 v_Probe;     // clip.xy, screen.xy
out vec4 v_Light;     // center.xyz, radius || range
out vec4 v_Color;
flat out float v_Slot;

#if defined(LIGHT_SPOT)
out vec4  v_Spot;     // direction.xyz, cos(inner)
out float v_Outer;     // cos(outer)
#endif

void main()
{
    vec2  Corner = ZyEmitRect(gl_VertexID);
    vec3  Center = a_Params0.xyz;
    float Extent = a_Params0.w;

    // A sphere reaches the length of each screen axis' world mix; summing instead bounds the box around it.
    vec2 Ex = (u_Camera * vec4(1.0, 0.0, 0.0, 0.0)).xy;
    vec2 Ey = (u_Camera * vec4(0.0, 1.0, 0.0, 0.0)).xy;
    vec2 Ez = (u_Camera * vec4(0.0, 0.0, 1.0, 0.0)).xy;

    vec2 Spread = vec2(length(vec3(Ex.x, Ey.x, Ez.x)), length(vec3(Ex.y, Ey.y, Ez.y)));

#if defined(LIGHT_SPOT)
    // A cone barely fills its range sphere, so bound the apex and the disc it opens onto instead.
    float Widest = Extent * sqrt(clamp(1.0 - a_Outer * a_Outer, 0.0, 1.0));
    vec2 Apex   = (u_Camera * vec4(Center, 1.0)).xy;
    vec2 Mouth  = (u_Camera * vec4(Center + a_Params1.xyz * Extent, 1.0)).xy;

    vec2 Lower  = min(Apex, Mouth - Widest * Spread);
    vec2 Upper  = max(Apex, Mouth + Widest * Spread);
    vec2 Clip   = mix(Lower, Upper, Corner);
#else
    vec4 Middle = u_Camera * vec4(Center, 1.0);
    vec2 Clip   = Middle.xy + (Corner * 2.0 - 1.0) * (Extent * Spread);
#endif

    gl_Position = vec4(Clip, 0.0, 1.0);

    v_Probe = vec4(Clip, Clip * 0.5 + 0.5);
    v_Light = a_Params0;
    v_Color = a_Color;
    v_Slot  = a_Slot;

#if defined(LIGHT_SPOT)
    v_Spot  = a_Params1;
    v_Outer = a_Outer;
#endif
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

uniform sampler2D t_Normal;
uniform sampler2D t_Depth;
uniform sampler2D t_Albedo;
uniform sampler2D t_Shadow;

in vec4 v_Probe;
in vec4 v_Light;
in vec4 v_Color;
flat in float v_Slot;

#if defined(LIGHT_SPOT)
in vec4 v_Spot;
in float v_Outer;
#endif

layout(location = 0) out vec3 out_Color;

/// Reads the atlas one angular step away from where a point lands in it.
float Reach(float Bearing, float Height, float Slot, vec2 Angular)
{
    float Along = clamp(Height + Angular.y / (2.0 * kShadowTangent), 0.0, 1.0);
    float Row   = ShadowRow(Slot, Along);

    return textureLod(t_Shadow, vec2(Bearing + Angular.x * ZY_INV_TWO_PI, Row), 0.0).r;
}

/// Reads back how much of the light survives the art standing between it and the point it lands on.
float Occlusion(vec3 World, vec3 Center, float Radius, float Slot, float Facing)
{
    vec3  Delta   = World - Center;
    float Radial  = length(Delta.xz);
    float Bearing = atan(Delta.z, Delta.x) * ZY_INV_TWO_PI + 0.5;

    float Height  = ShadowHeight(Delta.y / max(Radial, 0.0001));

    // A texel covers more ground the further out it is read, and a surface the light only grazes spans more
    // of one still, so the bias widens with both.
    float Sought  = Radial / max(Radius, 0.0001);
    float Bias    = (Sought * kShadowSlope + kShadowBias) / max(Facing, kShadowFacing);

    // Turning every pixel by a field of its own breaks the banding a small tap count leaves behind.
    float Rotate  = ZyGradientNoise(World * kDitherScale) * ZY_TWO_PI;

    // A light is a source of some size rather than a point, and this is how much of the sky it covers here.
    float Source  = kShadowSource / max(Sought, 0.0001);

    // Gather what stands in the way across that much sky, which is as wide as its shadow could ever spread.
    float Blocker = 0.0;
    float Found   = 0.0;

    for (int Step = 0; Step < kShadowSearch; ++Step)
    {
        float Nearest = Reach(Bearing, Height, Slot, ZySpiral(float(Step), float(kShadowSearch), Rotate) * Source);

        if (Nearest < Sought - Bias)
        {
            Blocker += Nearest;
            Found   += 1.0;
        }
    }

    // Nothing stands between the light and this point, so there is no edge here to soften.
    if (Found < 1.0)
    {
        return 1.0;
    }
    Blocker /= Found;

    // Art pressed against what it shades throws a sharp edge and the same art far in front of it throws a
    // soft one, so the gap between the two is the whole of the penumbra.
    float Penumbra = kShadowSource * (Sought - Blocker) / max(Blocker * Sought, 0.0001);
    float Spread   = clamp(Penumbra, kShadowMinimum, kShadowSpread);

    float Visible = 0.0;

    for (int Tap = 0; Tap < kShadowTaps; ++Tap)
    {
        float Nearest = Reach(Bearing, Height, Slot, ZySpiral(float(Tap), float(kShadowTaps), Rotate) * Spread);

        Visible += (Sought <= Nearest + Bias) ? 1.0 : 0.0;
    }

    return Visible / float(kShadowTaps);
}

void main()
{
    // Clip position and depth recover the world point through the inverse camera.
    ivec2 Texel  = ivec2(gl_FragCoord.xy);
    vec4  Base   = texelFetch(t_Albedo, Texel, 0);
    float Sorted = texelFetch(t_Depth, Texel, 0).r;
    float Depth  = Sorted - Base.a * kReliefRange / ZyDepthSpan(u_CameraInverse);
    vec4  Probe  = u_CameraInverse * vec4(v_Probe.xy, ZyClipDepth(Depth), 1.0);
    vec3  World  = Probe.xyz / Probe.w;

    vec3  Relative = v_Light.xyz - World;
    float  Distance = length(Relative);
    vec3  Incident = (Distance > 0.0001) ? Relative / Distance : vec3(0.0, 1.0, 0.0);

    float Attenuation = clamp(1.0 - pow(clamp(Distance / v_Light.w, 0.0, 1.0), v_Color.a), 0.0, 1.0);

#if defined(LIGHT_SPOT)
    float CosAngle = dot(-Incident, normalize(v_Spot.xyz));
    Attenuation *= smoothstep(v_Outer, v_Spot.w, CosAngle);
#endif

    // What the light never reached is dropped before the atlas is read.
    if (Attenuation < 0.001)
    {
        discard;
    }

    // Filtering a normal across an edge blends two surfaces, so read it by texel.
    vec3  Normal     = normalize(ZyDecodeNormalMap(texelFetch(t_Normal, Texel, 0).rgb));
    float NormalDotL = clamp(dot(Normal, Incident), 0.0, 1.0);

    // A surface turned away from the light is already dark, so it never pays to ask what stands in the way.
    if (NormalDotL < 0.001)
    {
        discard;
    }

    // Art standing between the light and this point takes the light away.
    if (v_Slot >= 0.0)
    {
        vec3 Lifted = World + Normal * kShadowLift;

        Attenuation *= Occlusion(Lifted, v_Light.xyz, v_Light.w, v_Slot, NormalDotL);

        if (Attenuation < 0.001)
        {
            discard;
        }
    }

    // The light shades the surface it lands on, so the radiance target holds scene color from the start.
    out_Color = Base.rgb * v_Color.rgb * (Attenuation * NormalDotL);
}

#endif // FRAGMENT_SHADER