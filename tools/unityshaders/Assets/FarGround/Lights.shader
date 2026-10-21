// FarGround/Lights: made from tools/shaderpack/fargroundlights.glsl by tools/unityshaders/port.py. Do not edit: edit the GLSL and run that again.
Shader "FarGround/Lights"
{
    Properties
    {

    }
    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            ZTest LEqual
            Cull Off

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 4.5
            #pragma only_renderers d3d11 glcore metal vulkan
            #include "UnityCG.cginc"

            // (the GLSL has each of the game's matrices as its four columns; HLSL has them as rows)
            #define hlslcc_mtx4x4unity_ObjectToWorld transpose(unity_ObjectToWorld)
            #define hlslcc_mtx4x4unity_WorldToObject transpose(unity_WorldToObject)
            #define hlslcc_mtx4x4unity_MatrixVP transpose(UNITY_MATRIX_VP)
            #define hlslcc_mtx4x4unity_MatrixV transpose(UNITY_MATRIX_V)
            #define SampleLod(S, uv, lod) S.SampleLevel(sampler##S, uv, lod)
            #define SampleFlat(S, uv) S.SampleLevel(sampler##S, uv, 0.0)
            #define SampleGradient(S, uv, dx, dy) S.SampleGrad(sampler##S, uv, dx, dy)
            #define Mod(x, y) ((x) - (y) * floor((x) / (y)))
            #define GreaterThan(a, b) ((a) > (b))
            #define GreaterThanEqual(a, b) ((a) >= (b))
            #define LessThan(a, b) ((a) < (b))
            #define LessThanEqual(a, b) ((a) <= (b))
            float4 TexelFetch(Texture2D t, int2 p, int lod) { return t.Load(int3(p, lod)); }
            float4 TexelFetch(Texture3D t, int3 p, int lod) { return t.Load(int4(p, lod)); }
            int2 TextureSize(Texture2D t, int lod) { uint w, h; t.GetDimensions(w, h); return int2(w, h); }
            bool AllZero(float4 v) { return !any(v); }
            // (one of a vector's numbers, chosen by a variable, read and given a new value: see chosen in tools/unityshaders/port.py)
            float Pick(float2 v, int n) { return n <= 0 ? v.x : v.y; }
            float Pick(float3 v, int n) { return n <= 0 ? v.x : n == 1 ? v.y : v.z; }
            float Pick(float4 v, int n) { return n <= 0 ? v.x : n == 1 ? v.y : n == 2 ? v.z : v.w; }
            float2 Put(float2 v, int n, float x) { return float2(n == 0 ? x : v.x, n == 1 ? x : v.y); }
            float3 Put(float3 v, int n, float x) { return float3(n == 0 ? x : v.x, n == 1 ? x : v.y, n == 2 ? x : v.z); }
            float4 Put(float4 v, int n, float x) { return float4(n == 0 ? x : v.x, n == 1 ? x : v.y, n == 2 ? x : v.z, n == 3 ? x : v.w); }
            // gl_FragCoord: which pixel is being drawn, its rows counted from the bottom, as every picture's are read here. Direct3D counts
            // the rows of what it draws into from the top, and the game draws into its pictures upside down to make up for it (saying so with
            // _ProjectionParams.x at -1): so where it is drawing straight to the screen, the row is turned over, or each picture read by pixel
            // (the camera's depth, the smoke drawn small) would be read upside down.
            float4 FragCoord(float4 pos)
            {
            #if UNITY_UV_STARTS_AT_TOP
                if (_ProjectionParams.x > 0.0) pos.y = _ScreenParams.y - pos.y;
            #endif
                return pos;
            }

            float4 _FGUp;     // as fargrounddraw.glsl
            float4 _FGNorth;
            float4 _FGEast;
            float4 _FGRound;
            float4 _FGCam;
            float4 _FGRow0;
            float4 _FGRow1;
            float4 _FGRow2;
            float4 _FGRow3;
            float4 _FGPush;
            float4 _FGCut;
            float4 _FGSun;     // xyz: towards the sun (the PQS's frame), as EVE's _SunDir is in the world's
            float4 _FGCityMask;     // EVE's alphaMask1: which of its map's channels the lights are in
            float4 _FGCity;     // x: EVE's _CityOverlayDetailScale, y: its _PlanetOpacity, z: 1 where its map is the cube's six faces
            Texture2D _FGPoints; SamplerState sampler_FGPoints;
            TextureCube _FGCityMap; SamplerState sampler_FGCityMap;     // EVE's cube_CityOverlayTex (MAP_TYPE_CUBE_1)
            Texture2D _FGCityXN; SamplerState sampler_FGCityXN;     // EVE's cube_CityOverlayTexxn ... zp (MAP_TYPE_CUBE6_1)
            Texture2D _FGCityXP; SamplerState sampler_FGCityXP;
            Texture2D _FGCityYN; SamplerState sampler_FGCityYN;
            Texture2D _FGCityYP; SamplerState sampler_FGCityYP;
            Texture2D _FGCityZN; SamplerState sampler_FGCityZN;
            Texture2D _FGCityZP; SamplerState sampler_FGCityZP;
            Texture2D _FGCityDark; SamplerState sampler_FGCityDark;     // EVE's _CityDarkOverlayDetailTex (the lights by night)
            Texture2D _FGCityLight; SamplerState sampler_FGCityLight;     // EVE's _CityLightOverlayDetailTex (the towns by day)

            struct v2f
            {
                float4 pos : SV_POSITION;
                float4 vs_TEXCOORD0 : TEXCOORD0;
                float3 vs_TEXCOORD4 : TEXCOORD4;
                float3 vs_TEXCOORD5 : TEXCOORD5;
            };

            // Far Ground's rings once more, for EVE's city lights (src/FarGround): where EVE is installed with its city lights on Kerbin, it
            // lays a second material over every quad of the game's ground ("EVE/TerrainCityLight", by EVE's MaterialPQS): by night the
            // lights of towns where its map has them, by day their grey; beyond the game's own ground the far ground stands in its place, and
            // without this they would end there. Drawn just after the rings, at exactly their places (the same sums as fargrounddraw.glsl,
            // so that its depth test meets theirs), and blended over them as EVE's is over the game's ground. EVE's own programs read out of
            // its bundle (EnvironmentalVisualEnhancements/eveshaders.bundle, the variants ALPHAMAP_1 MAP_TYPE_CUBE_1, its map of the lights a
            // cube, and ALPHAMAP_1 MAP_TYPE_CUBE6_1, the cube's six faces as six pictures: the owner's) and written again here, sum for sum,
            // with the far ground's inputs: where EVE takes the quad's point from the world's centre (its uv and uv2, the PQS's frame) and its
            // vertex colour's alpha, these take the ring's point and how high it looks.

            v2f vert(float3 in_POSITION0 : POSITION)
            {
                v2f OUT = (v2f)0;
                int k = int(in_POSITION0.x + 0.5), ri = int(in_POSITION0.y + 0.5);
                int around = int(_FGPush.y + 0.5), rings = int(_FGRound.w + 0.5);
                OUT.vs_TEXCOORD0 = ((float4)(0.0)); OUT.vs_TEXCOORD4 = float3(0.0, 0.0, 1.0); OUT.vs_TEXCOORD5 = float3(0.0, 0.0, -1.0);
                if (ri >= rings || k >= around) { OUT.pos = float4(0.0, 0.0, _FGPush.w, 1.0); return OUT; }
                float4 t = TexelFetch(_FGPoints, int2(k, ri), 0);
                float arc = min(_FGNorth.w * exp(_FGEast.w * float(ri)), _FGRound.z);
                float az = _FGRound.x + _FGRound.y * float(k);
                float3 d = normalize(_FGUp.xyz * cos(arc) + (_FGNorth.xyz * cos(az) + _FGEast.xyz * sin(az)) * sin(arc));
                float3 p = d * (_FGCam.w + t.r);
                float3 rel = p - _FGCam.xyz;
                // (placed as fargrounddraw.glsl places them, sum for sum)
                float howFar = length(rel);
                float push = min((_FGPush.x - 1.0) * howFar, _FGPush.z) * (1.0 - smoothstep(0.85 * _FGCut.w, _FGCut.w, length(normalize(p) - _FGCut.xyz)));
                float4 v = float4(rel * (1.0 + push / max(howFar, 1.0)), 1.0);
                OUT.vs_TEXCOORD0 = float4(0.0, 0.0, 0.0, t.b);
                OUT.vs_TEXCOORD4 = d;
                OUT.vs_TEXCOORD5 = -p;
                OUT.pos = float4(dot(_FGRow0, v), dot(_FGRow1, v) * _ProjectionParams.x, dot(_FGRow2, v), dot(_FGRow3, v));
                return OUT;
            }

            float4 frag(v2f IN) : SV_Target
            {
                float4 result = float4(0.0, 0.0, 0.0, 0.0);
                // (how much of night it is there: none while the sun is up, all once it is a tenth below, EVE's way)
                float3 sun = normalize(_FGSun.xyz);
                float s = dot(IN.vs_TEXCOORD4, sun);
                float low = clamp(floor(s + 1.00999999), 0.0, 1.0) - 1.0;
                float keep = clamp(s * -10.0, 0.0, 1.0) * low + 1.0;
                float night = 1.0 - clamp(dot(normalize(IN.vs_TEXCOORD4), sun) * 2.0 * keep, 0.0, 1.0);
                // (the place on the face of the cube its direction is on, for the detail; the lights' map read by the direction itself)
                float3 n = normalize(IN.vs_TEXCOORD5);
                float xzMajor = max(abs(n.z), abs(n.x)) >= abs(n.y) ? 1.0 : 0.0;
                float zOverX = abs(n.z) >= abs(n.x) ? 1.0 : 0.0;
                float major = xzMajor * (zOverX * (n.z - n.x) + n.x - n.y) + n.y;
                float sgn = major > 0.0 ? 1.0 : (major < 0.0 ? -1.0 : 0.0);
                float3 face = xzMajor > 0.5 ? (zOverX > 0.5 ? float3(n.z, sgn * n.x, -n.y) : float3(n.x, -sgn * n.z, -n.y)) : float3(n.y, n.x, sgn * n.z);
                float2 onFace = face.yz * 0.5 / abs(face.x);
                float2 uv = (onFace + 0.5) * _FGCity.x;
                float2 at = uv - _FGCity.x * 0.5;
                float most = max(abs(at.y), abs(at.x)), least = min(abs(at.y), abs(at.x));
                float2 gx = float2(ddx(most), ddx(least)), gy = float2(ddy(most), ddy(least));
                float4 dark = SampleGradient(_FGCityDark, uv, gx, gy);
                float4 light = SampleGradient(_FGCityLight, uv, gx, gy);
                // (the lights' map: the cube read by the direction, or the face its direction is on, read at its place on that face with
                // the same care at the faces' edges, the face chosen by the largest of its parts and that part's sign)
                float4 map;
                float faceMost = max(abs(onFace.y), abs(onFace.x)), faceLeast = min(abs(onFace.y), abs(onFace.x));
                float2 fx = float2(ddx(faceMost), ddx(faceLeast)), fy = float2(ddy(faceMost), ddy(faceLeast));
                if (_FGCity.z > 0.5) {
                    float2 fuv = onFace + 0.5;
                    float pos = sgn >= 0.0 ? 1.0 : 0.0;
                    float4 zf = lerp(SampleGradient(_FGCityZN, fuv, fx, fy), SampleGradient(_FGCityZP, fuv, fx, fy), pos);
                    float4 xf = lerp(SampleGradient(_FGCityXN, fuv, fx, fy), SampleGradient(_FGCityXP, fuv, fx, fy), pos);
                    float4 yf = lerp(SampleGradient(_FGCityYN, fuv, fx, fy), SampleGradient(_FGCityYP, fuv, fx, fy), pos);
                    map = lerp(yf, lerp(xf, zf, zOverX), xzMajor);
                } else map = SampleFlat(_FGCityMap, n);
                float towns = dot(map, _FGCityMask) * (0.0 >= IN.vs_TEXCOORD0.w ? 0.0 : 1.0);
                light.w *= towns;
                dark.w = night * towns * dark.w;
                float4 c = dark.wwww * (dark - light) + light;
                result = float4(c.xyz, c.w * _FGCity.y);
                return result;
            }
            ENDCG
        }
    }
}
