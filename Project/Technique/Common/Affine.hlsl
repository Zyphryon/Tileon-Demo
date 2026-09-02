// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifndef TILEON_AFFINE_INCLUDED
#define TILEON_AFFINE_INCLUDED

/// \brief Represents the local axes an instance is laid down along, and the point it stands at.
struct Affine
{
    /// The world direction the instance's own X travels.
    float3 ColumnX;

    /// The world direction the instance's own Y travels.
    float3 ColumnY;

    /// The world direction the instance's own Z travels.
    float3 ColumnZ;

    /// The point the instance stands at.
    float3 Origin;
};

/// \brief Reads the affine out of the three rows an instance carries it as.
///
/// \param Row0 The first row of the affine.
/// \param Row1 The second row of the affine.
/// \param Row2 The third row of the affine.
///
/// \return The local axes the art is laid down along, and the point it stands at.
Affine ReadAffine(float4 Row0, float4 Row1, float4 Row2)
{
    Affine Result;

    Result.ColumnX = float3(Row0.x, Row1.x, Row2.x);
    Result.ColumnY = float3(Row0.y, Row1.y, Row2.y);
    Result.ColumnZ = float3(Row0.z, Row1.z, Row2.z);
    Result.Origin  = float3(Row0.w, Row1.w, Row2.w);

    return Result;
}

/// \brief Carries a point out of an instance's own space and into the world.
///
/// \param Transform The local axes the instance is laid down along.
/// \param Local     The point to carry, in the instance's own space.
///
/// \return The point, in the world.
float3 ApplyAffine(Affine Transform, float3 Local)
{
    return Transform.Origin + Local.x * Transform.ColumnX + Local.y * Transform.ColumnY + Local.z * Transform.ColumnZ;
}

#endif // TILEON_AFFINE_INCLUDED