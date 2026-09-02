// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "Embedded://Shader/Vertex.hlsl"
#include "Embedded://Shader/Depth.hlsl"
#include "Embedded://Shader/Noise.hlsl"
#include "Embedded://Shader/Packing.hlsl"
#include "Resources://Technique/Common/Scene.hlsl"
#include "Resources://Technique/Common/Shadow.hlsl"

static const float kDitherScale     = 128.0;

static const int   kShadowSearch    = 8;
static const int   kShadowTaps      = 16;
static const float kShadowSource    = 0.05;
static const float kShadowSpread    = 0.06;
static const float kShadowMinimum   = 0.004;
static const float kShadowFacing    = 0.3;
static const float kShadowSlope     = 0.03;
static const float kShadowBias      = 0.004;
static const float kShadowLift      = 0.25;

struct vs_Input
{
    uint   VertexID  : SV_VertexID;
    float4 Params0   : SLOT0;    // center.xyz, radius || range
#if defined(LIGHT_SPOT)
    float4 Params1   : SLOT1;    // direction.xyz, cos(inner)
#endif
    float4 Color     : SLOT2;    // rgb, falloff
#if defined(LIGHT_SPOT)
    float  Outer     : SLOT3;    // cos(outer)
#endif
    float  Slot      : SLOT4;    // band of the shadow atlas, or -1 when the light casts none
};

struct fs_Input
{
    float4 Position  : SV_POSITION;
    float4 Probe     : TEXCOORD0;    // clip.xy, screen.xy
    float4 Light     : TEXCOORD1;    // center.xyz, radius || range
    float4 Color     : COLOR0;
#if defined(LIGHT_SPOT)
    float4 Spot      : TEXCOORD2;    // direction.xyz, cos(inner)
    float  Outer     : TEXCOORD3;    // cos(outer)
#endif
    nointerpolation float Slot : TEXCOORD4;
};

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Vertex Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef VERTEX_SHADER

fs_Input main(vs_Input Input)
{
    fs_Input Result;

    const float2 Corner = ZyEmitRect(Input.VertexID);
    const float3 Center = Input.Params0.xyz;
    const float  Extent = Input.Params0.w;

    // A sphere reaches the length of each screen axis' world mix; summing instead bounds the box around it.
    const float2 Ex = mul(u_Camera, float4(1.0, 0.0, 0.0, 0.0)).xy;
    const float2 Ey = mul(u_Camera, float4(0.0, 1.0, 0.0, 0.0)).xy;
    const float2 Ez = mul(u_Camera, float4(0.0, 0.0, 1.0, 0.0)).xy;

    const float2 Spread = float2(length(float3(Ex.x, Ey.x, Ez.x)), length(float3(Ex.y, Ey.y, Ez.y)));

#if defined(LIGHT_SPOT)
    // A cone barely fills its range sphere, so bound the apex and the disc it opens onto instead.
    const float  Widest = Extent * sqrt(saturate(1.0 - Input.Outer * Input.Outer));
    const float2 Apex   = mul(u_Camera, float4(Center, 1.0)).xy;
    const float2 Mouth  = mul(u_Camera, float4(Center + Input.Params1.xyz * Extent, 1.0)).xy;

    const float2 Lower  = min(Apex, Mouth - Widest * Spread);
    const float2 Upper  = max(Apex, Mouth + Widest * Spread);
    const float2 Clip   = lerp(Lower, Upper, Corner);
#else
    const float4 Middle = mul(u_Camera, float4(Center, 1.0));
    const float2 Clip   = Middle.xy + (Corner * 2.0 - 1.0) * (Extent * Spread);
#endif

    Result.Position = float4(Clip, 0.0, 1.0);
    Result.Probe    = float4(Clip, Clip * float2(0.5, -0.5) + 0.5);
    Result.Light    = Input.Params0;
    Result.Color    = Input.Color;
    Result.Slot     = Input.Slot;

#if defined(LIGHT_SPOT)
    Result.Spot     = Input.Params1;
    Result.Outer    = Input.Outer;
#endif

    return Result;
}

#endif // VERTEX_SHADER

// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Fragment Shader
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifdef FRAGMENT_SHADER

Texture2D    t_Normal : register(t0);
SamplerState s_Normal : register(s0);
Texture2D    t_Depth  : register(t1);
SamplerState s_Depth  : register(s1);
Texture2D    t_Albedo : register(t2);
SamplerState s_Albedo : register(s2);
Texture2D    t_Shadow : register(t3);
SamplerState s_Shadow : register(s3);

/// Reads the atlas one angular step away from where a point lands in it.
float Reach(float Bearing, float Height, float Slot, float2 Angular)
{
    const float Along = saturate(Height + Angular.y / (2.0 * kShadowTangent));
    const float Row   = ShadowRow(Slot, Along);

    return t_Shadow.SampleLevel(s_Shadow, float2(Bearing + Angular.x * ZY_INV_TWO_PI, Row), 0).r;
}

/// Reads back how much of the light survives the art standing between it and the point it lands on.
float Occlusion(float3 World, float3 Center, float Radius, float Slot, float Facing)
{
    const float3 Delta   = World - Center;
    const float  Radial  = length(Delta.xz);
    const float  Bearing = atan2(Delta.z, Delta.x) * ZY_INV_TWO_PI + 0.5;

    const float  Height  = ShadowHeight(Delta.y / max(Radial, 0.0001));

    // A texel covers more ground the further out it is read, and a surface the light only grazes spans more
    // of one still, so the bias widens with both.
    const float  Sought  = Radial / max(Radius, 0.0001);
    const float  Bias    = (Sought * kShadowSlope + kShadowBias) / max(Facing, kShadowFacing);

    // Turning every pixel by a field of its own breaks the banding a small tap count leaves behind.
    const float  Rotate  = ZyGradientNoise(World * kDitherScale) * ZY_TWO_PI;

    // A light is a source of some size rather than a point, and this is how much of the sky it covers here.
    const float  Source  = kShadowSource / max(Sought, 0.0001);

    // Gather what stands in the way across that much sky, which is as wide as its shadow could ever spread.
    float Blocker = 0.0;
    float Found   = 0.0;

    [unroll]
    for (int Step = 0; Step < kShadowSearch; ++Step)
    {
        const float Nearest = Reach(Bearing, Height, Slot, ZySpiral(Step, kShadowSearch, Rotate) * Source);

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
    const float Penumbra = kShadowSource * (Sought - Blocker) / max(Blocker * Sought, 0.0001);
    const float Spread   = clamp(Penumbra, kShadowMinimum, kShadowSpread);

    float Visible = 0.0;

    [unroll]
    for (int Tap = 0; Tap < kShadowTaps; ++Tap)
    {
        const float Nearest = Reach(Bearing, Height, Slot, ZySpiral(Tap, kShadowTaps, Rotate) * Spread);

        Visible += (Sought <= Nearest + Bias) ? 1.0 : 0.0;
    }

    return Visible / float(kShadowTaps);
}

float3 main(fs_Input Input) : SV_Target0
{
    // Clip position and depth recover the world point through the inverse camera.
    const int3   Texel  = int3(Input.Position.xy, 0);
    const float4 Base   = t_Albedo.Load(Texel);
    const float  Sorted = t_Depth.Load(Texel).r;
    const float  Depth  = Sorted - Base.a * kReliefRange / ZyDepthSpan(u_CameraInverse);
    const float4 Probe  = mul(u_CameraInverse, float4(Input.Probe.xy, ZyClipDepth(Depth), 1.0));
    const float3 World  = Probe.xyz / Probe.w;

    const float3 Relative = Input.Light.xyz - World;
    const float  Distance = length(Relative);
    const float3 Incident = (Distance > 0.0001) ? Relative / Distance : float3(0.0, 1.0, 0.0);

    float Attenuation = saturate(1.0 - pow(saturate(Distance / Input.Light.w), Input.Color.a));

#if defined(LIGHT_SPOT)
    const float CosAngle = dot(-Incident, normalize(Input.Spot.xyz));
    Attenuation *= smoothstep(Input.Outer, Input.Spot.w, CosAngle);
#endif

    // What the light never reached is dropped before the atlas is read.
    clip(Attenuation - 0.001);

    // Filtering a normal across an edge blends two surfaces, so read it by texel.
    const float3 Normal     = normalize(ZyDecodeNormalMap(t_Normal.Load(Texel).rgb));
    const float  NormalDotL = saturate(dot(Normal, Incident));

    // A surface turned away from the light is already dark, so it never pays to ask what stands in the way.
    clip(NormalDotL - 0.001);

    // Art standing between the light and this point takes the light away.
    if (Input.Slot >= 0.0)
    {
        const float3 Lifted = World + Normal * kShadowLift;

        Attenuation *= Occlusion(Lifted, Input.Light.xyz, Input.Light.w, Input.Slot, NormalDotL);

        clip(Attenuation - 0.001);
    }

    // The light shades the surface it lands on, so the radiance target holds scene color from the start.
    return Base.rgb * Input.Color.rgb * (Attenuation * NormalDotL);
}

#endif // FRAGMENT_SHADER