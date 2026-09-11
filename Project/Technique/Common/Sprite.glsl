// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifndef TILEON_SPRITE_INCLUDED
#define TILEON_SPRITE_INCLUDED

#include "Scene.glsl"
#include "Embedded://Shader/Affine.glsl"

/// The bit that lays the art down mirrored across its own width.
const uint kMirrorX      = 1u;

/// The bit that lays the art down mirrored across its own height.
const uint kMirrorY      = 2u;

/// Where the pair of bits naming the plane the art is laid against begins.
const uint kPlaneShift   = 2u;

/// The pair of bits naming the plane the art is laid against.
const uint kPlaneMask    = 3u;

/// The bit that says the art already carries the projection, and has to land unsheared.
const uint kUnsheared    = 16u;

/// The bit that says the art tiles across the card as the card is stretched, rather than stretching with it.
const uint kTiled        = 32u;

/// Where the layer of a layered material begins in the orientation word.
const uint kLayerShift   = 20u;

/// The width of an outline's stroke begins here, and is held to the three bits above it.
const uint kStrokeShift  = 6u;

/// The mask the width of an outline's stroke is held to, which is seven pixels of art at the widest.
const uint kStrokeMask   = 7u;









/// The art stands up, facing the eye.
const uint kPlaneUpright = 0u;

/// The art lies flat on the ground.
const uint kPlaneGround  = 1u;

/// The art stands on the other side the camera sees, facing along the ground instead of across it.
const uint kPlaneSide     = 2u;

/// \brief Represents the face an instance turns towards, and the pair of directions its art spans.
struct Face
{
    /// The plane the art is laid against.
    uint Plane;

    /// The art's own width, before the projection is folded into it.
    vec3 AxisU;

    /// The art's own height, before the projection is folded into it.
    vec3 AxisV;

    /// The face the art turns towards, pointing out of it.
    vec3 Normal;

    /// What one unit of the art's width covers once it lands.
    vec3 SpanU;

    /// What one unit of the art's height covers once it lands.
    vec3 SpanV;

    /// Whether the art is a side seen edge-on with the projection in it: a run lying along z.
    bool Edge;
};

/// \brief Reads which way an instance faces and what its art spans.
///
/// \param Orientation The instance's orientation word.
/// \param Transform The local axes the art is laid down along.
///
/// \return The face the art turns towards, and the pair of directions it spans.
Face ReadFace(uint Orientation, ZyAffine Transform)
{
    Face Result;

    Result.Plane  = (Orientation >> kPlaneShift) & kPlaneMask;

    bool Unsheared = (Orientation & kUnsheared) != 0u;
	
    // A side seen edge-on with the projection in its art is a run lying along the ground, x across and z along,
    // so it stands nowhere, stretches with the z scale, and its tiles repeat along it; only its normal is the eye's.
    Result.Edge   = Unsheared && Result.Plane == kPlaneSide;

    Result.AxisU  = (Result.Plane == kPlaneSide && !Result.Edge)  ? Transform.ColumnZ : Transform.ColumnX;
    Result.AxisV  = (Result.Plane == kPlaneGround || Result.Edge) ? Transform.ColumnZ : Transform.ColumnY;
    Result.Normal = (Result.Plane == kPlaneGround) ? Transform.ColumnY
                  : (Result.Plane == kPlaneSide)   ? Transform.ColumnX : -Transform.ColumnZ;

    Result.SpanU  = (Unsheared && !Result.Edge) ? u_ScreenX.xyz * length(Result.AxisU) : Result.AxisU;
    Result.SpanV  = (Unsheared && !Result.Edge) ? u_ScreenY.xyz * length(Result.AxisV) : Result.AxisV;

    // Its map was authored in that same frame, so the face it turns towards is the eye, whatever its plane says.
    if (Unsheared)
    {
        Result.Normal = -(u_CameraInverse * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
    }

    return Result;
}

/// \brief Places one corner of an instance's quad in the world.
///
/// \param Transform The local axes the art is laid down along.
/// \param Surface   The face the art turns towards, and the pair of directions it spans.
/// \param Corner    The corner to place, over zero through one on both axes.
/// \param Size      The extent the art covers along each of the two directions it spans.
///
/// \return The corner, in the world.
vec3 PlaceCorner(ZyAffine Transform, Face Surface, vec2 Corner, vec2 Size)
{
    return Transform.Origin + Corner.x * Size.x * Surface.SpanU + Corner.y * Size.y * Surface.SpanV;
}

/// \brief Picks the point in the frame a corner reads, turning it over for a mirrored instance.
///
/// \param Orientation The instance's orientation word.
/// \param Corner The corner to read, over zero through one on both axes.
///
/// \return The point in the frame, over zero through one on both axes.
vec2 ReadSample(uint Orientation, vec2 Corner)
{
    vec2 Result = vec2(Corner.x, 1.0 - Corner.y);

    if ((Orientation & kMirrorX) != 0u)
    {
        Result.x = 1.0 - Result.x;
    }
    if ((Orientation & kMirrorY) != 0u)
    {
        Result.y = 1.0 - Result.y;
    }

    return Result;
}

#endif // TILEON_SPRITE_INCLUDED