// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
// Copyright (C) 2025-2026 by Agustin L. Alvarez. All rights reserved.
//
// This work is proprietary and confidential. Unauthorized copying, distribution, modification or use of this
// file, in whole or in part, is strictly prohibited without the prior written permission of the copyright holder.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#ifndef TILEON_SCENE_INCLUDED
#define TILEON_SCENE_INCLUDED

cbuffer cb_Global : register(b0)
{
    float4x4 u_Camera;          // Turns world space into clip space.
    float4x4 u_CameraInverse;   // Turns clip space back into world space.
    float4   u_ScreenX;         // The world direction one unit of screen width travels, and one over a clip depth unit.
    float4   u_ScreenY;         // The world direction one unit of screen height travels.
    float4   u_Origin;          // The whole-unit origin the of the frame, and the scene's clock.
};

/// The furthest a relief sink ever reaches, in world units, which is what the alpha of the scene's base color spans.
static const float kReliefRange = 0.5;

/// Returns the scene's clock.
float GetSceneTime()
{
    return u_Origin.w;
}

#endif // TILEON_SCENE_INCLUDED