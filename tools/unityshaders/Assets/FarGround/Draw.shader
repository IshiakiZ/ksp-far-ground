// FarGround/Draw: made from tools/shaderpack/fargrounddraw.glsl by tools/unityshaders/port.py. Do not edit: edit the GLSL and run that again.
Shader "FarGround/Draw"
{
    Properties
    {

    }
    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Pass
        {
            Blend OneMinusSrcAlpha SrcAlpha
            ZWrite On
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

            float4 _FGUp;     // xyz: the point under the camera (a unit vector, the PQS's frame)
            float4 _FGNorth;     // xyz: north there; w: the first ring's angle along the ground (radians)
            float4 _FGEast;     // xyz: the other way along the ground there (bearings grow towards it); w: the log of each ring's angle over the last's
            float4 _FGRound;     // x: the first point's bearing round a ring (radians from north), y: the step round, z: the last ring's angle (radians), w: rings
            float4 _FGCam;     // xyz: the camera from the world's centre (m, the PQS's frame); w: the world's radius (m)
            float4 _FGRow0;     // the rows of the matrix from the PQS's frame, the camera at its origin, to the screen
            float4 _FGRow1;
            float4 _FGRow2;
            float4 _FGRow3;
            float4 _FGPush;     // x: 1 + how much farther the ground is drawn than it is, where the game's own quads may be too; y: points round a ring; z: by no more than this (m); w: the depth beyond the far end, where a spare point is put (2 on OpenGL, -1 with Direct3D's depth the other way round)
            float4 _FGCut;     // xyz: the point the game builds its own ground round (a unit vector, the PQS's frame); w: how far round it its quads may reach (radians)
            float4 _FGAhead;     // xyz: the way the camera looks (the PQS's frame)
            float4 _FGWorldX;     // the rows of the turn from the PQS's frame to the scene's (the game lays its textures in the scene's)
            float4 _FGWorldY;
            float4 _FGWorldZ;
            float4 _FGTexAt;     // xyz: the world's centre in the textures' frame (the scene's, plus the floating origin's offset, in 100 km)
            float4 _FGFogSun;     // xyz: the game's _sunLightDirection (the PQS's frame), which its ground's fog ramp is read by
            float4 _FGSun;     // xyz: towards the sun (the PQS's frame); w: 1 to tint the far ground red, to see where it is
            float4 _FGSunLight;     // rgb: the sun's light on a face turned to it (_LightColor0)
            float4 _FGShA;     // the sky's light from the light probe, as Unity gives it to the game's ground (unity_SHAr/g/b, SHBr/g/b, SHC),
            float4 _FGShB;     // in the scene's frame
            float4 _FGShC;
            float4 _FGShD;
            float4 _FGShE;
            float4 _FGShF;
            float4 _FGShG;
            float4 _FGLook;     // x: saturation, y: contrast, z: _groundTexStart, w: _groundTexEnd (the ground material's)
            float4 _FGTint;     // its tint (rgb) and how much of it (a)
            float4 _FGPower;     // x: _powerNear, y: _powerFar, z: _steepPower, w: 1 + 2 + 4: low, high and steep texturing on
            float4 _FGSteep;     // x: _steepNearTiling, y: _steepTiling, z: _steepTexStart, w: _steepTexEnd
            float4 _FGTile;     // x: _lowNearTiling, y: _lowMultiFactor, z: _midNearTiling, w: _midMultiFactor
            float4 _FGTile2;     // x: _highNearTiling, y: _highMultiFactor
            float4 _FGBands;     // _lowStart, _lowEnd, _highStart, _highEnd
            float4 _FGFog;     // x: the game's _globalDensity, y: its _heightDensityAtViewer (the fog's thickness where the camera is); z: 1 where the ground's material has its fog on (AERIAL_ON); w: how far the far planet shows through the ground (the game's _PlanetOpacity as it has set it, the alpha, blended as the game's ground is: OneMinusSrcAlpha, SrcAlpha)
            Texture2D _FGPoints; SamplerState sampler_FGPoints;
            Texture2D _lowTex; SamplerState sampler_lowTex;
            Texture2D _midTex; SamplerState sampler_midTex;
            Texture2D _highTex; SamplerState sampler_highTex;
            Texture2D _steepTex; SamplerState sampler_steepTex;
            Texture2D _fogColorRamp; SamplerState sampler_fogColorRamp;

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 vs_TEXCOORD0 : TEXCOORD0;
                float3 vs_TEXCOORD1 : TEXCOORD1;
                float3 vs_TEXCOORD2 : TEXCOORD2;
                float3 vs_TEXCOORD3 : TEXCOORD3;
                float4 vs_TEXCOORD4 : TEXCOORD4;
            };

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
            // (a point of the rings: its place from the world's centre, its land colour (packed eight bits a part, see fargroundpoints.glsl)
            // and how high it looks)
            float3 place(int k, int ri, out float3 colour, out float looks)
            {
                float4 t = TexelFetch(_FGPoints, int2(k, ri), 0);
                float arc = min(_FGNorth.w * exp(_FGEast.w * float(ri)), _FGRound.z);
                float az = _FGRound.x + _FGRound.y * float(k);
                float bits = t.g;            // (not "packed": a word GLSL keeps, which NVIDIA's compiler refuses (the PC, 2026-10-20))
                colour = float3(floor(bits / 65536.0), Mod(floor(bits / 256.0), 256.0), Mod(bits, 256.0)) / 255.0;
                looks = t.b;
                return normalize(_FGUp.xyz * cos(arc) + (_FGNorth.xyz * cos(az) + _FGEast.xyz * sin(az)) * sin(arc)) * (_FGCam.w + t.r);
            }

            v2f vert(float3 in_POSITION0 : POSITION)
            {
                v2f OUT = (v2f)0;
                int k = int(in_POSITION0.x + 0.5), ri = int(in_POSITION0.y + 0.5);
                int around = int(_FGPush.y + 0.5), rings = int(_FGRound.w + 0.5);
                OUT.vs_TEXCOORD0 = float3(0.0, 0.0, 1.0); OUT.vs_TEXCOORD1 = ((float3)(0.0)); OUT.vs_TEXCOORD2 = ((float3)(0.0)); OUT.vs_TEXCOORD3 = ((float3)(0.0)); OUT.vs_TEXCOORD4 = ((float4)(0.0));
                // (points the mesh has beyond those drawn this frame, round a ring or out: put beyond the far end (_FGPush.w). Put nearer than
                // the near end, as z 2 is with Direct3D's depth the other way round, a triangle from a point drawn to one of these was drawn
                // halfway across the screen, nearer than anything: a dark band (the PC, 2026-10-20))
                if (ri >= rings || k >= around) { OUT.pos = float4(0.0, 0.0, _FGPush.w, 1.0); return OUT; }
                float3 colour, other;
                float looks, otherLooks;
                float3 p = place(k, ri, colour, looks);
                float3 pOut = place(k, ri + 1 < rings ? ri + 1 : ri - 1, other, otherLooks);
                float3 pRound = place(k + 1 < around ? k + 1 : k - 1, ri, other, otherLooks);
                float3 n = normalize(cross(pOut - p, pRound - p));
                if (dot(n, p) < 0.0) n = -n;
                float3 rel = p - _FGCam.xyz;
                // (a little farther than it is only where the game's own quads may be drawn too, so that they stand in front there, faded out
                // over the last part of their reach: elsewhere at its place, where the sea's surface, drawn after it, stood in front of low land
                // seen from high up at a slant)
                float howFar = length(rel);
                float push = min((_FGPush.x - 1.0) * howFar, _FGPush.z) * (1.0 - smoothstep(0.85 * _FGCut.w, _FGCut.w, length(normalize(p) - _FGCut.xyz)));
                float4 v = float4(rel * (1.0 + push / max(howFar, 1.0)), 1.0);
                float3 world = float3(dot(_FGWorldX.xyz, p), dot(_FGWorldY.xyz, p), dot(_FGWorldZ.xyz, p));
                float3 worldN = float3(dot(_FGWorldX.xyz, n), dot(_FGWorldY.xyz, n), dot(_FGWorldZ.xyz, n));
                OUT.vs_TEXCOORD0 = n; OUT.vs_TEXCOORD1 = colour;
                OUT.vs_TEXCOORD2 = world * 1e-5 + _FGTexAt.xyz;
                OUT.vs_TEXCOORD3 = worldN;
                // (the slope as the game's PQSMod_UVPlanetRelativePosition puts it in its points' second uv: 1 - up . normal; the fog's ramp read,
                // as the game's shader reads it, by the sun's direction against the way up there)
                OUT.vs_TEXCOORD4 = float4(dot(rel, _FGAhead.xyz), 1.0 - dot(normalize(p), n), looks, dot(_FGFogSun.xyz, normalize(p)));
                // (the rows are the camera's projection as it stands, not turned over: turned over here where the camera draws upside down, as
                // Unity's own matrices are)
                OUT.pos = float4(dot(_FGRow0, v), dot(_FGRow1, v) * _ProjectionParams.x, dot(_FGRow2, v), dot(_FGRow3, v));
                return OUT;
            }

            // (a texture laid three ways, as the game's shader lays it: across the scene's yz, xz and xy planes, weighted by the normal's
            // unsigned parts, which it does not make add up to one)
            float3 tri(Texture2D t, SamplerState samplert, float3 at, float3 w)
            {
                return SampleFlat(t, at.xy).rgb * w.z + SampleFlat(t, at.zy).rgb * w.x + SampleFlat(t, at.zx).rgb * w.y;
            }
            float smooth01(float x) { x = clamp(x, 0.0, 1.0); return x * x * (3.0 - 2.0 * x); }

            float4 frag(v2f IN) : SV_Target
            {
                float4 result = float4(0.0, 0.0, 0.0, 0.0);
                float3 n = normalize(IN.vs_TEXCOORD0), nw = normalize(IN.vs_TEXCOORD3), w = abs(IN.vs_TEXCOORD3), P = IN.vs_TEXCOORD2;
                float depth = IN.vs_TEXCOORD4.x, slope = IN.vs_TEXCOORD4.y;
                int flags = int(_FGPower.w + 0.5);
                // (the land colour, as the game's vertex half puts it: saturation about its luma, then contrast about the tint)
                float3 c = IN.vs_TEXCOORD1;
                float luma = dot(c, float3(0.299, 0.587, 0.114));
                c = (luma + _FGLook.x * (c - luma) - _FGTint.rgb * _FGTint.a) * _FGLook.y + _FGTint.rgb * _FGTint.a;
                // (the height bands, from how high the place looks: the land colour's alpha, as the game's land layer makes it)
                float alpha = IN.vs_TEXCOORD4.z;
                float high = (flags & 2) != 0 ? smooth01((alpha - _FGBands.z) / (_FGBands.w - _FGBands.z)) : 0.0;
                float lowS = (flags & 1) != 0 ? smooth01((alpha - _FGBands.x) / (_FGBands.y - _FGBands.x)) : 1.0;
                float mid = lowS - high, low = 1.0 - lowS;
                float far = smooth01((depth - _FGLook.z) / (_FGLook.w - _FGLook.z));
                float steep = (flags & 4) != 0 ? clamp(slope * _FGPower.z, 0.0, 1.0) * (1.0 - smooth01((depth - _FGSteep.z) / (_FGSteep.w - _FGSteep.z))) : 0.0;
                float nearPow = (1.0 - far) * _FGPower.x, farPow = far * _FGPower.y;
                float3 sum = ((float3)(0.0));
                if (nearPow > 0.0)
                {
                    if (low > 0.0) sum += tri(_lowTex, sampler_lowTex, P * _FGTile.x, w) * (nearPow * low);
                    if (mid > 0.0) sum += tri(_midTex, sampler_midTex, P * _FGTile.z, w) * (nearPow * mid);
                    if (high > 0.0) sum += tri(_highTex, sampler_highTex, P * _FGTile2.x, w) * (nearPow * high);
                }
                if (farPow > 0.0)
                {
                    if (low > 0.0) sum += tri(_lowTex, sampler_lowTex, P * _FGTile.y, w) * (farPow * low);
                    if (mid > 0.0) sum += tri(_midTex, sampler_midTex, P * _FGTile.w, w) * (farPow * mid);
                    if (high > 0.0) sum += tri(_highTex, sampler_highTex, P * _FGTile2.y, w) * (farPow * high);
                }
                float3 albedo = c + (nearPow + farPow) * (c * sum - c);
                if (steep > 0.0)
                {
                    if (far < 1.0) albedo = lerp(albedo, tri(_steepTex, sampler_steepTex, P * _FGSteep.x, w), (1.0 - far) * steep);
                    if (far > 0.0) albedo = lerp(albedo, tri(_steepTex, sampler_steepTex, P * _FGSteep.y, w), far * steep);
                }
                // (the ground's own fog, where its material has it: towards the colour of the fog's ramp for the sun's height there, by how far
                // along the camera's axis, before the light, as the game's shader does it)
                if (_FGFog.z > 0.5)
                {
                    float3 fogColour = SampleFlat(_fogColorRamp, float2(IN.vs_TEXCOORD4.w, 0.5)).rgb;
                    albedo = lerp(albedo, fogColour, 1.0 - exp(depth * _FGFog.x * _FGFog.y));
                }
                // (the light: the sun on the face, and the sky's from the probe's harmonics as Unity's ShadeSH9 has them, then made gamma as
                // the game's ground has it, the game drawing in gamma)
                float4 n4 = float4(nw, 1.0);
                float3 sky = float3(dot(_FGShA, n4), dot(_FGShB, n4), dot(_FGShC, n4));
                float4 nn = nw.xyzz * nw.yzzx;
                sky += float3(dot(_FGShD, nn), dot(_FGShE, nn), dot(_FGShF, nn));
                sky += _FGShG.rgb * (nw.x * nw.x - nw.y * nw.y);
                sky = max(exp2(log2(max(sky, ((float3)(0.0)))) * 0.416666657) * 1.05499995 - 0.0549999997, ((float3)(0.0)));
                float3 lit_ = albedo * (_FGSunLight.rgb * max(dot(n, _FGSun.xyz), 0.0) + sky);
                if (_FGSun.w > 0.5) lit_ = lerp(lit_, float3(1.0, 0.1, 0.1), 0.35);
                result = float4(lit_, _FGFog.w);
                return result;
            }
            ENDCG
        }
    }
}
