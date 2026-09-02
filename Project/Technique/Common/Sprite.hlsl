// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifndef TILEON_SPRITE_INCLUDED
#define TILEON_SPRITE_INCLUDED

#include "Scene.hlsl"
#include "Affine.hlsl"

/// The bit that lays the art down mirrored across its own width.
static const uint kMirrorX    = 1u;

/// The bit that lays the art down mirrored across its own height.
static const uint kMirrorY    = 2u;

/// Where the pair of bits naming the plane the art is laid against begins.
static const uint kPlaneShift = 2u;

/// The pair of bits naming the plane the art is laid against.
static const uint kPlaneMask  = 3u;

/// The bit that says the art already carries the projection, and has to land unsheared.
static const uint kUnsheared  = 16u;

/// The art stands up, facing the eye.
static const uint kPlaneUpright     = 0u;

/// The art lies flat on the ground.
static const uint kPlaneGround      = 1u;

/// The art stands on the other side the camera sees, facing along the ground instead of across it.
static const uint kPlaneSide        = 2u;

/// \brief Represents the face an instance turns towards, and the pair of directions its art spans.
struct Face
{
    /// The plane the art is laid against.
    uint   Plane;

    /// The art's own width, before the projection is folded into it.
    float3 AxisU;

    /// The art's own height, before the projection is folded into it.
    float3 AxisV;

    /// The face the art turns towards, pointing out of it.
    float3 Normal;

    /// What one unit of the art's width covers once it lands.
    float3 SpanU;

    /// What one unit of the art's height covers once it lands.
    float3 SpanV;
};

/// \brief Reads which way an instance faces and what its art spans.
///
/// \param Orientation The instance's orientation word.
/// \param Transform The local axes the art is laid down along.
///
/// \return The face the art turns towards, and the pair of directions it spans.
Face ReadFace(uint Orientation, Affine Transform)
{
    Face Result;

    Result.Plane  = (Orientation >> kPlaneShift) & kPlaneMask;

    Result.AxisU  = (Result.Plane == kPlaneSide)   ? Transform.ColumnZ : Transform.ColumnX;
    Result.AxisV  = (Result.Plane == kPlaneGround) ? Transform.ColumnZ : Transform.ColumnY;
    Result.Normal = (Result.Plane == kPlaneGround) ? Transform.ColumnY
                  : (Result.Plane == kPlaneSide)   ? Transform.ColumnX : -Transform.ColumnZ;

    // Art carrying the projection already spans the screen, so it blocks along the same pair of directions.
    const bool Unsheared = (Orientation & kUnsheared) != 0u;

    Result.SpanU  = Unsheared ? u_ScreenX.xyz * length(Transform.ColumnX) : Result.AxisU;
    Result.SpanV  = Unsheared ? u_ScreenY.xyz * length(Transform.ColumnY) : Result.AxisV;

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
float3 PlaceCorner(Affine Transform, Face Surface, float2 Corner, float2 Size)
{
    return Transform.Origin + Corner.x * Size.x * Surface.SpanU + Corner.y * Size.y * Surface.SpanV;
}

/// \brief Picks the point in the frame a corner reads, turning it over for a mirrored instance.
///
/// \param Orientation The instance's orientation word.
/// \param Corner The corner to read, over zero through one on both axes.
///
/// \return The point in the frame, over zero through one on both axes.
float2 ReadSample(uint Orientation, float2 Corner)
{
    float2 Result = float2(Corner.x, 1.0 - Corner.y);

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