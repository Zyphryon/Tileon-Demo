// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Tileon contributors (see AUTHORS.md)
//
// This work is licensed under the terms of the MIT license.
//
// For a copy, see <https://opensource.org/licenses/MIT>.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifndef TILEON_SCENE_INCLUDED
#define TILEON_SCENE_INCLUDED

layout(std140, binding = 0) uniform cb_Global
{
    mat4 u_Camera;          // Turns world space into clip space.
    mat4 u_CameraInverse;   // Turns clip space back into world space.
    vec4 u_ScreenX;         // The world direction one unit of screen width travels.
    vec4 u_ScreenY;         // The world direction one unit of screen height travels.
};

/// The furthest a relief sink ever reaches, in world units, which is what the alpha of the scene's base color spans.
const float kReliefRange = 0.5;

#endif // TILEON_SCENE_INCLUDED