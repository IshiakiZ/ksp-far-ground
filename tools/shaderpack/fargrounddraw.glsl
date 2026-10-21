#ifdef VERTEX
#version 150
// Far Ground's rings (src/FarGround; research/rendering/experiments/far-ground-lab.md): each point of the rings round the camera
// read from the points' picture (fargroundpoints.glsl: the ground's
// height, land colour and how high it looks there), lifted to its height, its slope from its neighbours outward and round; drawn
// a little farther than it is where the game's own quads may be drawn too, so that they stand in front there. Shaded as the game's own
// ground shader ("Terrain/PQS/PQS Main Shader" as the owner's Kerbin has it, read out of the game's data:
// research/rendering/notes/far-ground.md) shades its ground: the land colour put through the material's saturation, contrast
// and tint; its textures laid three ways over the world near and far, by the bands of how high it looks and by slope; its own
// fog where the material has it (AERIAL_ON: towards the colour of the sky's ramp for the sun's height there, by distance), before
// the light; the sun on the face and the sky's light from the light probe. Left out: its bump maps (far off they hardly show).
// The air over it is Scatterer's, which goes by the camera's depth picture: see fargrounddepth.glsl.
uniform vec4 _FGUp;          // xyz: the point under the camera (a unit vector, the PQS's frame)
uniform vec4 _FGNorth;       // xyz: north there; w: the first ring's angle along the ground (radians)
uniform vec4 _FGEast;        // xyz: the other way along the ground there (bearings grow towards it); w: the log of each ring's angle over the last's
uniform vec4 _FGRound;       // x: the first point's bearing round a ring (radians from north), y: the step round, z: the last ring's angle (radians), w: rings
uniform vec4 _FGCam;         // xyz: the camera from the world's centre (m, the PQS's frame); w: the world's radius (m)
uniform vec4 _FGRow0;        // the rows of the matrix from the PQS's frame, the camera at its origin, to the screen
uniform vec4 _FGRow1;
uniform vec4 _FGRow2;
uniform vec4 _FGRow3;
uniform vec4 _FGPush;        // x: 1 + how much farther the ground is drawn than it is, where the game's own quads may be too; y: points round a ring; z: by no more than this (m); w: the depth beyond the far end, where a spare point is put (2 on OpenGL, -1 with Direct3D's depth the other way round)
uniform vec4 _FGCut;         // xyz: the point the game builds its own ground round (a unit vector, the PQS's frame); w: how far round it its quads may reach (radians)
uniform vec4 _FGAhead;       // xyz: the way the camera looks (the PQS's frame)
uniform vec4 _FGWorldX;      // the rows of the turn from the PQS's frame to the scene's (the game lays its textures in the scene's)
uniform vec4 _FGWorldY;
uniform vec4 _FGWorldZ;
uniform vec4 _FGTexAt;       // xyz: the world's centre in the textures' frame (the scene's, plus the floating origin's offset, in 100 km)
uniform vec4 _FGFogSun;      // xyz: the game's _sunLightDirection (the PQS's frame), which its ground's fog ramp is read by
uniform vec4 _ProjectionParams;  // x: -1 where the camera draws upside down (Direct3D, into a picture of its own), else 1
uniform sampler2D _FGPoints;
in vec3 in_POSITION0;        // x: the point's place round its ring, y: its ring
out vec3 vs_TEXCOORD0;       // the ground's normal (the PQS's frame)
out vec3 vs_TEXCOORD1;       // its land colour
out vec3 vs_TEXCOORD2;       // where it is in the textures' frame (100 km)
out vec3 vs_TEXCOORD3;       // the normal in the scene's frame (its unsigned parts weigh the textures; the sky's light goes by it)
out vec4 vs_TEXCOORD4;       // x: how far it is along the camera's axis (m); y: its slope (1 - up . normal); z: how high it looks (the bands); w: where on the fog's ramp
// (a point of the rings: its place from the world's centre, its land colour (packed eight bits a part, see fargroundpoints.glsl)
// and how high it looks)
vec3 place(int k, int ri, out vec3 colour, out float looks)
{
    vec4 t = texelFetch(_FGPoints, ivec2(k, ri), 0);
    float arc = min(_FGNorth.w * exp(_FGEast.w * float(ri)), _FGRound.z);
    float az = _FGRound.x + _FGRound.y * float(k);
    float bits = t.g;            // (not "packed": a word GLSL keeps, which NVIDIA's compiler refuses (the PC, 2026-10-20))
    colour = vec3(floor(bits / 65536.0), mod(floor(bits / 256.0), 256.0), mod(bits, 256.0)) / 255.0;
    looks = t.b;
    return normalize(_FGUp.xyz * cos(arc) + (_FGNorth.xyz * cos(az) + _FGEast.xyz * sin(az)) * sin(arc)) * (_FGCam.w + t.r);
}
void main()
{
    int k = int(in_POSITION0.x + 0.5), ri = int(in_POSITION0.y + 0.5);
    int around = int(_FGPush.y + 0.5), rings = int(_FGRound.w + 0.5);
    vs_TEXCOORD0 = vec3(0.0, 0.0, 1.0); vs_TEXCOORD1 = vec3(0.0); vs_TEXCOORD2 = vec3(0.0); vs_TEXCOORD3 = vec3(0.0); vs_TEXCOORD4 = vec4(0.0);
    // (points the mesh has beyond those drawn this frame, round a ring or out: put beyond the far end (_FGPush.w). Put nearer than
    // the near end, as z 2 is with Direct3D's depth the other way round, a triangle from a point drawn to one of these was drawn
    // halfway across the screen, nearer than anything: a dark band (the PC, 2026-10-20))
    if (ri >= rings || k >= around) { gl_Position = vec4(0.0, 0.0, _FGPush.w, 1.0); return; }
    vec3 colour, other;
    float looks, otherLooks;
    vec3 p = place(k, ri, colour, looks);
    vec3 pOut = place(k, ri + 1 < rings ? ri + 1 : ri - 1, other, otherLooks);
    vec3 pRound = place(k + 1 < around ? k + 1 : k - 1, ri, other, otherLooks);
    vec3 n = normalize(cross(pOut - p, pRound - p));
    if (dot(n, p) < 0.0) n = -n;
    vec3 rel = p - _FGCam.xyz;
    // (a little farther than it is only where the game's own quads may be drawn too, so that they stand in front there, faded out
    // over the last part of their reach: elsewhere at its place, where the sea's surface, drawn after it, stood in front of low land
    // seen from high up at a slant)
    float howFar = length(rel);
    float push = min((_FGPush.x - 1.0) * howFar, _FGPush.z) * (1.0 - smoothstep(0.85 * _FGCut.w, _FGCut.w, length(normalize(p) - _FGCut.xyz)));
    vec4 v = vec4(rel * (1.0 + push / max(howFar, 1.0)), 1.0);
    vec3 world = vec3(dot(_FGWorldX.xyz, p), dot(_FGWorldY.xyz, p), dot(_FGWorldZ.xyz, p));
    vec3 worldN = vec3(dot(_FGWorldX.xyz, n), dot(_FGWorldY.xyz, n), dot(_FGWorldZ.xyz, n));
    vs_TEXCOORD0 = n; vs_TEXCOORD1 = colour;
    vs_TEXCOORD2 = world * 1e-5 + _FGTexAt.xyz;
    vs_TEXCOORD3 = worldN;
    // (the slope as the game's PQSMod_UVPlanetRelativePosition puts it in its points' second uv: 1 - up . normal; the fog's ramp read,
    // as the game's shader reads it, by the sun's direction against the way up there)
    vs_TEXCOORD4 = vec4(dot(rel, _FGAhead.xyz), 1.0 - dot(normalize(p), n), looks, dot(_FGFogSun.xyz, normalize(p)));
    // (the rows are the camera's projection as it stands, not turned over: turned over here where the camera draws upside down, as
    // Unity's own matrices are)
    gl_Position = vec4(dot(_FGRow0, v), dot(_FGRow1, v) * _ProjectionParams.x, dot(_FGRow2, v), dot(_FGRow3, v));
}
#endif
#ifdef FRAGMENT
#version 150
uniform vec4 _FGSun;         // xyz: towards the sun (the PQS's frame); w: 1 to tint the far ground red, to see where it is
uniform vec4 _FGSunLight;    // rgb: the sun's light on a face turned to it (_LightColor0)
uniform vec4 _FGShA;         // the sky's light from the light probe, as Unity gives it to the game's ground (unity_SHAr/g/b, SHBr/g/b, SHC),
uniform vec4 _FGShB;         // in the scene's frame
uniform vec4 _FGShC;
uniform vec4 _FGShD;
uniform vec4 _FGShE;
uniform vec4 _FGShF;
uniform vec4 _FGShG;
uniform vec4 _FGLook;        // x: saturation, y: contrast, z: _groundTexStart, w: _groundTexEnd (the ground material's)
uniform vec4 _FGTint;        // its tint (rgb) and how much of it (a)
uniform vec4 _FGPower;       // x: _powerNear, y: _powerFar, z: _steepPower, w: 1 + 2 + 4: low, high and steep texturing on
uniform vec4 _FGSteep;       // x: _steepNearTiling, y: _steepTiling, z: _steepTexStart, w: _steepTexEnd
uniform vec4 _FGTile;        // x: _lowNearTiling, y: _lowMultiFactor, z: _midNearTiling, w: _midMultiFactor
uniform vec4 _FGTile2;       // x: _highNearTiling, y: _highMultiFactor
uniform vec4 _FGBands;       // _lowStart, _lowEnd, _highStart, _highEnd
uniform vec4 _FGFog;         // x: the game's _globalDensity, y: its _heightDensityAtViewer (the fog's thickness where the camera is); z: 1 where the ground's material has its fog on (AERIAL_ON); w: how far the far planet shows through the ground (the game's _PlanetOpacity as it has set it, the alpha, blended as the game's ground is: OneMinusSrcAlpha, SrcAlpha)
uniform sampler2D _lowTex;
uniform sampler2D _midTex;
uniform sampler2D _highTex;
uniform sampler2D _steepTex;
uniform sampler2D _fogColorRamp;
in vec3 vs_TEXCOORD0;
in vec3 vs_TEXCOORD1;
in vec3 vs_TEXCOORD2;
in vec3 vs_TEXCOORD3;
in vec4 vs_TEXCOORD4;
out vec4 SV_Target0;
// (a texture laid three ways, as the game's shader lays it: across the scene's yz, xz and xy planes, weighted by the normal's
// unsigned parts, which it does not make add up to one)
vec3 tri(sampler2D t, vec3 at, vec3 w)
{
    return texture(t, at.xy).rgb * w.z + texture(t, at.zy).rgb * w.x + texture(t, at.zx).rgb * w.y;
}
float smooth01(float x) { x = clamp(x, 0.0, 1.0); return x * x * (3.0 - 2.0 * x); }
void main()
{
    vec3 n = normalize(vs_TEXCOORD0), nw = normalize(vs_TEXCOORD3), w = abs(vs_TEXCOORD3), P = vs_TEXCOORD2;
    float depth = vs_TEXCOORD4.x, slope = vs_TEXCOORD4.y;
    int flags = int(_FGPower.w + 0.5);
    // (the land colour, as the game's vertex half puts it: saturation about its luma, then contrast about the tint)
    vec3 c = vs_TEXCOORD1;
    float luma = dot(c, vec3(0.299, 0.587, 0.114));
    c = (luma + _FGLook.x * (c - luma) - _FGTint.rgb * _FGTint.a) * _FGLook.y + _FGTint.rgb * _FGTint.a;
    // (the height bands, from how high the place looks: the land colour's alpha, as the game's land layer makes it)
    float alpha = vs_TEXCOORD4.z;
    float high = (flags & 2) != 0 ? smooth01((alpha - _FGBands.z) / (_FGBands.w - _FGBands.z)) : 0.0;
    float lowS = (flags & 1) != 0 ? smooth01((alpha - _FGBands.x) / (_FGBands.y - _FGBands.x)) : 1.0;
    float mid = lowS - high, low = 1.0 - lowS;
    float far = smooth01((depth - _FGLook.z) / (_FGLook.w - _FGLook.z));
    float steep = (flags & 4) != 0 ? clamp(slope * _FGPower.z, 0.0, 1.0) * (1.0 - smooth01((depth - _FGSteep.z) / (_FGSteep.w - _FGSteep.z))) : 0.0;
    float nearPow = (1.0 - far) * _FGPower.x, farPow = far * _FGPower.y;
    vec3 sum = vec3(0.0);
    if (nearPow > 0.0)
    {
        if (low > 0.0) sum += tri(_lowTex, P * _FGTile.x, w) * (nearPow * low);
        if (mid > 0.0) sum += tri(_midTex, P * _FGTile.z, w) * (nearPow * mid);
        if (high > 0.0) sum += tri(_highTex, P * _FGTile2.x, w) * (nearPow * high);
    }
    if (farPow > 0.0)
    {
        if (low > 0.0) sum += tri(_lowTex, P * _FGTile.y, w) * (farPow * low);
        if (mid > 0.0) sum += tri(_midTex, P * _FGTile.w, w) * (farPow * mid);
        if (high > 0.0) sum += tri(_highTex, P * _FGTile2.y, w) * (farPow * high);
    }
    vec3 albedo = c + (nearPow + farPow) * (c * sum - c);
    if (steep > 0.0)
    {
        if (far < 1.0) albedo = mix(albedo, tri(_steepTex, P * _FGSteep.x, w), (1.0 - far) * steep);
        if (far > 0.0) albedo = mix(albedo, tri(_steepTex, P * _FGSteep.y, w), far * steep);
    }
    // (the ground's own fog, where its material has it: towards the colour of the fog's ramp for the sun's height there, by how far
    // along the camera's axis, before the light, as the game's shader does it)
    if (_FGFog.z > 0.5)
    {
        vec3 fogColour = texture(_fogColorRamp, vec2(vs_TEXCOORD4.w, 0.5)).rgb;
        albedo = mix(albedo, fogColour, 1.0 - exp(depth * _FGFog.x * _FGFog.y));
    }
    // (the light: the sun on the face, and the sky's from the probe's harmonics as Unity's ShadeSH9 has them, then made gamma as
    // the game's ground has it, the game drawing in gamma)
    vec4 n4 = vec4(nw, 1.0);
    vec3 sky = vec3(dot(_FGShA, n4), dot(_FGShB, n4), dot(_FGShC, n4));
    vec4 nn = nw.xyzz * nw.yzzx;
    sky += vec3(dot(_FGShD, nn), dot(_FGShE, nn), dot(_FGShF, nn));
    sky += _FGShG.rgb * (nw.x * nw.x - nw.y * nw.y);
    sky = max(exp2(log2(max(sky, vec3(0.0))) * 0.416666657) * 1.05499995 - 0.0549999997, vec3(0.0));
    vec3 lit = albedo * (_FGSunLight.rgb * max(dot(n, _FGSun.xyz), 0.0) + sky);
    if (_FGSun.w > 0.5) lit = mix(lit, vec3(1.0, 0.1, 0.1), 0.35);
    SV_Target0 = vec4(lit, _FGFog.w);
}
#endif
