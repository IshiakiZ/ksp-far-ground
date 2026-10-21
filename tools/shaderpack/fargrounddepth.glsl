#ifdef VERTEX
#version 150
// Far Ground's rings again, for the camera's depth picture only (src/FarGround): drawn into it just after the
// game has made it (CameraEvent.AfterDepthTexture), as far off as the rings stand (fargrounddraw.glsl, whose placing this is). The
// game makes that picture in a pass of its own, from the things it draws itself: what a command buffer draws is not in it, and
// Scatterer, which lays the air over the ground by that picture, took the far ground's pixels for sky and laid no air over them
// (the main chat, 2026-10-18: "a very dark olive with no haze", where the game's own ground there is hazy blue-green). The colour
// is left as it is: only how far off is written, the nearer kept.
uniform vec4 _FGUp;          // as fargrounddraw.glsl
uniform vec4 _FGNorth;
uniform vec4 _FGEast;
uniform vec4 _FGRound;
uniform vec4 _FGCam;
uniform vec4 _FGRow0;
uniform vec4 _FGRow1;
uniform vec4 _FGRow2;
uniform vec4 _FGRow3;
uniform vec4 _FGPush;
uniform vec4 _FGCut;
uniform vec4 _ProjectionParams;
uniform sampler2D _FGPoints;
in vec3 in_POSITION0;        // x: the point's place round its ring, y: its ring
void main()
{
    int k = int(in_POSITION0.x + 0.5), ri = int(in_POSITION0.y + 0.5);
    int around = int(_FGPush.y + 0.5), rings = int(_FGRound.w + 0.5);
    if (ri >= rings || k >= around) { gl_Position = vec4(0.0, 0.0, _FGPush.w, 1.0); return; }
    vec4 t = texelFetch(_FGPoints, ivec2(k, ri), 0);
    float arc = min(_FGNorth.w * exp(_FGEast.w * float(ri)), _FGRound.z);
    float az = _FGRound.x + _FGRound.y * float(k);
    vec3 p = normalize(_FGUp.xyz * cos(arc) + (_FGNorth.xyz * cos(az) + _FGEast.xyz * sin(az)) * sin(arc)) * (_FGCam.w + t.r);
    vec3 rel = p - _FGCam.xyz;
    // (placed as fargrounddraw.glsl places them, sum for sum)
    float howFar = length(rel);
    float push = min((_FGPush.x - 1.0) * howFar, _FGPush.z) * (1.0 - smoothstep(0.85 * _FGCut.w, _FGCut.w, length(normalize(p) - _FGCut.xyz)));
    vec4 v = vec4(rel * (1.0 + push / max(howFar, 1.0)), 1.0);
    gl_Position = vec4(dot(_FGRow0, v), dot(_FGRow1, v) * _ProjectionParams.x, dot(_FGRow2, v), dot(_FGRow3, v));
}
#endif
#ifdef FRAGMENT
#version 150
out vec4 SV_Target0;
void main()
{
    SV_Target0 = vec4(0.0);
}
#endif
