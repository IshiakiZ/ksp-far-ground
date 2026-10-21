#ifdef VERTEX
#version 150
// Far Ground's rings once more, for EVE's city lights (src/FarGround): where EVE is installed with its city lights on Kerbin, it
// lays a second material over every quad of the game's ground ("EVE/TerrainCityLight", by EVE's MaterialPQS): by night the
// lights of towns where its map has them, by day their grey; beyond the game's own ground the far ground stands in its place, and
// without this they would end there. Drawn just after the rings, at exactly their places (the same sums as fargrounddraw.glsl,
// so that its depth test meets theirs), and blended over them as EVE's is over the game's ground. EVE's own programs read out of
// its bundle (EnvironmentalVisualEnhancements/eveshaders.bundle, the variants ALPHAMAP_1 MAP_TYPE_CUBE_1, its map of the lights a
// cube, and ALPHAMAP_1 MAP_TYPE_CUBE6_1, the cube's six faces as six pictures: the owner's) and written again here, sum for sum,
// with the far ground's inputs: where EVE takes the quad's point from the world's centre (its uv and uv2, the PQS's frame) and its
// vertex colour's alpha, these take the ring's point and how high it looks.
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
out vec4 vs_TEXCOORD0;       // w: how high the place looks (the land colour's alpha, as EVE reads the vertex colour's)
out vec3 vs_TEXCOORD4;       // the way up there (the PQS's frame)
out vec3 vs_TEXCOORD5;       // the point's place from the world's centre, turned the other way, as EVE has it (the PQS's frame)
void main()
{
    int k = int(in_POSITION0.x + 0.5), ri = int(in_POSITION0.y + 0.5);
    int around = int(_FGPush.y + 0.5), rings = int(_FGRound.w + 0.5);
    vs_TEXCOORD0 = vec4(0.0); vs_TEXCOORD4 = vec3(0.0, 0.0, 1.0); vs_TEXCOORD5 = vec3(0.0, 0.0, -1.0);
    if (ri >= rings || k >= around) { gl_Position = vec4(0.0, 0.0, _FGPush.w, 1.0); return; }
    vec4 t = texelFetch(_FGPoints, ivec2(k, ri), 0);
    float arc = min(_FGNorth.w * exp(_FGEast.w * float(ri)), _FGRound.z);
    float az = _FGRound.x + _FGRound.y * float(k);
    vec3 d = normalize(_FGUp.xyz * cos(arc) + (_FGNorth.xyz * cos(az) + _FGEast.xyz * sin(az)) * sin(arc));
    vec3 p = d * (_FGCam.w + t.r);
    vec3 rel = p - _FGCam.xyz;
    // (placed as fargrounddraw.glsl places them, sum for sum)
    float howFar = length(rel);
    float push = min((_FGPush.x - 1.0) * howFar, _FGPush.z) * (1.0 - smoothstep(0.85 * _FGCut.w, _FGCut.w, length(normalize(p) - _FGCut.xyz)));
    vec4 v = vec4(rel * (1.0 + push / max(howFar, 1.0)), 1.0);
    vs_TEXCOORD0 = vec4(0.0, 0.0, 0.0, t.b);
    vs_TEXCOORD4 = d;
    vs_TEXCOORD5 = -p;
    gl_Position = vec4(dot(_FGRow0, v), dot(_FGRow1, v) * _ProjectionParams.x, dot(_FGRow2, v), dot(_FGRow3, v));
}
#endif
#ifdef FRAGMENT
#version 150
uniform vec4 _FGSun;         // xyz: towards the sun (the PQS's frame), as EVE's _SunDir is in the world's
uniform vec4 _FGCityMask;    // EVE's alphaMask1: which of its map's channels the lights are in
uniform vec4 _FGCity;        // x: EVE's _CityOverlayDetailScale, y: its _PlanetOpacity, z: 1 where its map is the cube's six faces
uniform samplerCube _FGCityMap;      // EVE's cube_CityOverlayTex (MAP_TYPE_CUBE_1)
uniform sampler2D _FGCityXN;         // EVE's cube_CityOverlayTexxn ... zp (MAP_TYPE_CUBE6_1)
uniform sampler2D _FGCityXP;
uniform sampler2D _FGCityYN;
uniform sampler2D _FGCityYP;
uniform sampler2D _FGCityZN;
uniform sampler2D _FGCityZP;
uniform sampler2D _FGCityDark;       // EVE's _CityDarkOverlayDetailTex (the lights by night)
uniform sampler2D _FGCityLight;      // EVE's _CityLightOverlayDetailTex (the towns by day)
in vec4 vs_TEXCOORD0;
in vec3 vs_TEXCOORD4;
in vec3 vs_TEXCOORD5;
out vec4 SV_Target0;
void main()
{
    // (how much of night it is there: none while the sun is up, all once it is a tenth below, EVE's way)
    vec3 sun = normalize(_FGSun.xyz);
    float s = dot(vs_TEXCOORD4, sun);
    float low = clamp(floor(s + 1.00999999), 0.0, 1.0) - 1.0;
    float keep = clamp(s * -10.0, 0.0, 1.0) * low + 1.0;
    float night = 1.0 - clamp(dot(normalize(vs_TEXCOORD4), sun) * 2.0 * keep, 0.0, 1.0);
    // (the place on the face of the cube its direction is on, for the detail; the lights' map read by the direction itself)
    vec3 n = normalize(vs_TEXCOORD5);
    float xzMajor = max(abs(n.z), abs(n.x)) >= abs(n.y) ? 1.0 : 0.0;
    float zOverX = abs(n.z) >= abs(n.x) ? 1.0 : 0.0;
    float major = xzMajor * (zOverX * (n.z - n.x) + n.x - n.y) + n.y;
    float sgn = major > 0.0 ? 1.0 : (major < 0.0 ? -1.0 : 0.0);
    vec3 face = xzMajor > 0.5 ? (zOverX > 0.5 ? vec3(n.z, sgn * n.x, -n.y) : vec3(n.x, -sgn * n.z, -n.y)) : vec3(n.y, n.x, sgn * n.z);
    vec2 onFace = face.yz * 0.5 / abs(face.x);
    vec2 uv = (onFace + 0.5) * _FGCity.x;
    vec2 at = uv - _FGCity.x * 0.5;
    float most = max(abs(at.y), abs(at.x)), least = min(abs(at.y), abs(at.x));
    vec2 gx = vec2(dFdx(most), dFdx(least)), gy = vec2(dFdy(most), dFdy(least));
    vec4 dark = textureGrad(_FGCityDark, uv, gx, gy);
    vec4 light = textureGrad(_FGCityLight, uv, gx, gy);
    // (the lights' map: the cube read by the direction, or the face its direction is on, read at its place on that face with
    // the same care at the faces' edges, the face chosen by the largest of its parts and that part's sign)
    vec4 map;
    float faceMost = max(abs(onFace.y), abs(onFace.x)), faceLeast = min(abs(onFace.y), abs(onFace.x));
    vec2 fx = vec2(dFdx(faceMost), dFdx(faceLeast)), fy = vec2(dFdy(faceMost), dFdy(faceLeast));
    if (_FGCity.z > 0.5) {
        vec2 fuv = onFace + 0.5;
        float pos = sgn >= 0.0 ? 1.0 : 0.0;
        vec4 zf = mix(textureGrad(_FGCityZN, fuv, fx, fy), textureGrad(_FGCityZP, fuv, fx, fy), pos);
        vec4 xf = mix(textureGrad(_FGCityXN, fuv, fx, fy), textureGrad(_FGCityXP, fuv, fx, fy), pos);
        vec4 yf = mix(textureGrad(_FGCityYN, fuv, fx, fy), textureGrad(_FGCityYP, fuv, fx, fy), pos);
        map = mix(yf, mix(xf, zf, zOverX), xzMajor);
    } else map = texture(_FGCityMap, n);
    float towns = dot(map, _FGCityMask) * (0.0 >= vs_TEXCOORD0.w ? 0.0 : 1.0);
    light.w *= towns;
    dark.w = night * towns * dark.w;
    vec4 c = dark.wwww * (dark - light) + light;
    SV_Target0 = vec4(c.xyz, c.w * _FGCity.y);
}
#endif
