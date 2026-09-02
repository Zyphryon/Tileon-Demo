// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifndef TILEON_SHADOW_INCLUDED
#define TILEON_SHADOW_INCLUDED

#include "Embedded://Shader/Math.hlsl"

/// The count of lights the atlas holds a band for.
static const uint   kShadowCasters   = 32u;

/// The steepest elevation a band reaches, as a tangent either side of the horizon.
static const float  kShadowTangent   = 2.0;

/// The count of rows a single band is written over.
static const float  kShadowElevation = 128.0;

/// The count of bits the band an instance lands in is named by.
static const uint   kShadowSlotBits  = 6u;

/// Where the bits naming the band an instance lands in begin.
static const uint   kFacingSlotShift = 8u;

/// The bits naming the band an instance lands in.
static const uint   kFacingSlotMask  = (1u << kShadowSlotBits) - 1u;

/// The bit that marks an instance as the copy carrying whatever ran off the end of the map.
static const uint   kFacingWrap      = 1u << (kFacingSlotShift + kShadowSlotBits);

/// Every corner of a quad that has nothing to carry is put here, off the map and with no area to cover.
static const float4 kShadowDiscarded = float4(-2.0, -2.0, 0.0, 1.0);

/// \brief Represents where a point lands across the map, and the bearing its quad is unwrapped about.
struct Arc
{
    /// The bearing the quad is unwrapped about, in radians.
    float Pivot;

    /// Where that bearing lands across the map, over zero through one.
    float Anchor;

    /// Where the point itself lands across the map, over zero through one.
    float Across;
};

/// \brief Places an elevation in the band, over zero at the bottom through one at the top.
///
/// \note The band is written against the tangent of the elevation, so a lookup has to ask for it the same way.
///
/// \param Tangent The elevation to place, as a tangent either side of the horizon.
///
/// \return The elevation, over zero through one up the band.
float ShadowHeight(float Tangent)
{
    return clamp(Tangent / kShadowTangent, -1.0, 1.0) * 0.5 + 0.5;
}

/// \brief Places a point in the band its caster owns, over zero through one down the whole atlas.
///
/// \param Slot   The band the caster owns.
/// \param Height The elevation, over zero through one up that band.
///
/// \return The row, over zero through one down the atlas.
float ShadowRow(float Slot, float Height)
{
    return (Slot + (Height * (kShadowElevation - 1.0) + 0.5) / kShadowElevation) / float(kShadowCasters);
}

/// \brief Measures how far around the caster a point sits from the bearing its quad is unwrapped about.
///
/// \param Point  The point to measure.
/// \param Caster The light the quad is unwrapped around.
/// \param Pivot  The bearing the quad is unwrapped about, in radians.
///
/// \return The turn from the pivot to the point, inside the half turn either side of zero.
float ShadowSwing(float3 Point, float3 Caster, float Pivot)
{
    return ZyWrapAngle(atan2(Point.z - Caster.z, Point.x - Caster.x) - Pivot);
}

/// \brief Unwraps a point of a quad around its caster.
///
/// \param Point  The point to unwrap.
/// \param Origin The point the quad as a whole stands at.
/// \param Caster The light the quad is unwrapped around.
///
/// \return Where the point lands across the map, and the bearing it was unwrapped about.
Arc ReadArc(float3 Point, float3 Origin, float3 Caster)
{
    Arc Result;

    Result.Pivot  = atan2(Origin.z - Caster.z, Origin.x - Caster.x);
    Result.Anchor = Result.Pivot * ZY_INV_TWO_PI + 0.5;
    Result.Across = Result.Anchor + ShadowSwing(Point, Caster, Result.Pivot) * ZY_INV_TWO_PI;

    return Result;
}

/// \brief Checks whether the whole of a quad already lands on the map, leaving its copy nothing to carry.
///
/// \param Anchor The bearing the quad is unwrapped about, over zero through one across the map.
/// \param Lowest The turn of the corner that sits furthest one way from that bearing.
/// \param Widest The turn of the corner that sits furthest the other way.
///
/// \return `true` when every corner already lands on the map.
bool ShadowFits(float Anchor, float Lowest, float Widest)
{
    return (Anchor + Lowest * ZY_INV_TWO_PI >= 0.0) && (Anchor + Widest * ZY_INV_TWO_PI <= 1.0);
}

/// \brief Places a corner of the atlas, which the two APIs walk down in opposite directions.
///
/// \param Across The bearing, over zero through one across the map.
/// \param Row    The row, over zero through one down the atlas.
///
/// \return The corner, in clip space.
float4 PlaceAtlas(float Across, float Row)
{
    return float4(Across * 2.0 - 1.0, 1.0 - Row * 2.0, 0.0, 1.0);
}

#endif // TILEON_SHADOW_INCLUDED