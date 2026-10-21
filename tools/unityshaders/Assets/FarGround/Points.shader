// FarGround/Points: made from tools/shaderpack/fargroundpoints.glsl by tools/unityshaders/port.py. Do not edit: edit the GLSL and run that again.
Shader "FarGround/Points"
{
    Properties
    {

    }
    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Pass
        {
            Blend One Zero
            ZWrite Off
            ZTest Always
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

            float4 _FGSheet;     // xy: 1 (the sheet covers the picture), z: its depth, w: 1
            float4 _FGUp;     // xyz: the point under the camera (a unit vector, the PQS's frame)
            float4 _FGNorth;     // xyz: north there; w: the first ring's angle along the ground (radians)
            float4 _FGEast;     // xyz: the other way along the ground there (bearings grow towards it); w: the log of each ring's angle over the last's
            float4 _FGRound;     // x: the first point's bearing round a ring (radians from north), y: the step round, z: the last ring's angle (radians), w: rings
            float4 _FGPush;     // y: the points round a ring drawn this frame (the picture is made with room to spare, round and out)
            float4 _KDecals;
            float4 _KFlats;
            Texture2D _KMap; SamplerState sampler_KMap;
            Texture2D _KTables; SamplerState sampler_KTables;
            Texture2D _KDecalMaps; SamplerState sampler_KDecalMaps;

            struct v2f
            {
                float4 pos : SV_POSITION;
            };

            // Far Ground's points (src/FarGround; research/rendering/experiments/far-ground-lab.md): a picture with a pixel a point of the
            // rings round the camera (the points round a ring across, the rings up), each Kerbin's own height, land colour and how high it
            // looks there, worked out from the game's layers: its height map, its three noise layers, its decals (the space centre's
            // ground, the airfields', the old space centre's, the pyramids'), its land classes. Written by
            // research/rendering/lab/kerbinground.swift (fargroundglsl) from its model of Kerbin (kerbin.swift, checked against the game's
            // own points and its own drawn ground): not to be edited by hand.
            // Simplex tables, rows 1 on of _KTables, by seed: 121214 14554 454545 1247389 121221 44473 4563456 453737 44445 1 973572 8687 6858 17857 435345 248775058 453453435 212121 47373 768453

            v2f vert(float3 in_POSITION0 : POSITION)
            {
                v2f OUT = (v2f)0;
                OUT.pos = float4(in_POSITION0.xy * _FGSheet.xy, _FGSheet.z, _FGSheet.w);
                return OUT;
            }

            int kp(int t, int i) { return int(TexelFetch(_KTables, int2(i & 255, 1 + t), 0).r); }
            int kfloor(float x) { return !(x > 0.0) ? int(x) - 1 : int(x); }
            float kcorner(int g, float3 x) {
                float t = 0.6 - dot(x, x);
                if (t < 0.0) return 0.0;
                t *= t;
                float3 gr = g < 4 ? float3(float(1 - 2 * (g & 1)), float(1 - 2 * ((g >> 1) & 1)), 0.0)
                        : (g < 8 ? float3(float(1 - 2 * (g & 1)), 0.0, float(1 - 2 * ((g >> 1) & 1)))
                                 : float3(0.0, float(1 - 2 * (g & 1)), float(1 - 2 * ((g >> 1) & 1))));
                return t * t * dot(gr, x);
            }
            float ksimplexValue(int t, float3 v) {
                const float G3 = 1.0 / 6.0;
                float s = (v.x + v.y + v.z) * (1.0 / 3.0);
                int i = kfloor(v.x + s), j = kfloor(v.y + s), k = kfloor(v.z + s);
                float tt = float(i + j + k) * G3;
                float3 x0 = v - (float3(float(i), float(j), float(k)) - tt);
                int3 o1, o2;
                if (x0.x >= x0.y) {
                    if (x0.y >= x0.z) { o1 = int3(1, 0, 0); o2 = int3(1, 1, 0); }
                    else if (x0.x >= x0.z) { o1 = int3(1, 0, 0); o2 = int3(1, 0, 1); }
                    else { o1 = int3(0, 0, 1); o2 = int3(1, 0, 1); }
                } else if (x0.y < x0.z) { o1 = int3(0, 0, 1); o2 = int3(0, 1, 1); }
                else if (x0.x < x0.z) { o1 = int3(0, 1, 0); o2 = int3(0, 1, 1); }
                else { o1 = int3(0, 1, 0); o2 = int3(1, 1, 0); }
                float3 x1 = x0 - ((float3)(o1)) + G3, x2 = x0 - ((float3)(o2)) + 2.0 * G3, x3 = x0 - 1.0 + 3.0 * G3;
                int ii = i & 255, jj = j & 255, kk = k & 255;
                int g0 = kp(t, ii + kp(t, jj + kp(t, kk))) % 12;
                int g1 = kp(t, ii + o1.x + kp(t, jj + o1.y + kp(t, kk + o1.z))) % 12;
                int g2 = kp(t, ii + o2.x + kp(t, jj + o2.y + kp(t, kk + o2.z))) % 12;
                int g3 = kp(t, ii + 1 + kp(t, jj + 1 + kp(t, kk + 1))) % 12;
                return 32.0 * (kcorner(g0, x0) + kcorner(g1, x1) + kcorner(g2, x2) + kcorner(g3, x3));
            }
            float ksimplex(int t, float3 d, float octaves, float persistence, float frequency) {
                float total = 0.0, amplitude = 1.0, f = frequency, most = 0.0;
                { [loop] for (float n = 0.0; n < octaves; n += 1.0) {
                    total += ksimplexValue(t, d * f) * amplitude;
                    f *= 2.0; most += amplitude; amplitude *= persistence;
                } }
                return total / most;
            }
            float kgradient(float3 p, int3 c, int seed) {
                uint n = uint(c.x) * 1619u + uint(c.y) * 31337u + uint(c.z) * 6971u + uint(seed) * 1013u;
                n ^= n >> 8u;
                return dot(TexelFetch(_KTables, int2(int(n & 255u), 0), 0).xyz, p - ((float3)(c))) * 2.12;
            }
            float kcoherent(float3 p, int seed, bool smoothed) {
                int3 c = int3(kfloor(p.x), kfloor(p.y), kfloor(p.z));
                float3 a = p - ((float3)(c));
                if (smoothed) a = a * a * (3.0 - 2.0 * a);
                float x0 = lerp(kgradient(p, c, seed), kgradient(p, c + int3(1, 0, 0), seed), a.x);
                float x1 = lerp(kgradient(p, c + int3(0, 1, 0), seed), kgradient(p, c + int3(1, 1, 0), seed), a.x);
                float x2 = lerp(kgradient(p, c + int3(0, 0, 1), seed), kgradient(p, c + int3(1, 0, 1), seed), a.x);
                float x3 = lerp(kgradient(p, c + int3(0, 1, 1), seed), kgradient(p, c + int3(1, 1, 1), seed), a.x);
                return lerp(lerp(x0, x1, a.y), lerp(x2, x3, a.y), a.z);
            }
            float kridged(float3 d, float frequency, float lacunarity, int octaves, int seed, bool smoothed) {
                float3 p = d * frequency;
                float v = 0.0, weight = 1.0, sw = 1.0;
                { [loop] for (int i = 0; i < octaves; i++) {
                    float signal = 1.0 - abs(kcoherent(p, (seed + i) & 0x7FFFFFFF, smoothed));
                    signal *= signal; signal *= weight;
                    weight = clamp(signal * 2.0, 0.0, 1.0);
                    v += signal * sw;
                    sw /= lacunarity; p *= lacunarity;
                } }
                return v * 1.25 - 1.0;
            }
            float khermite(float s, float v0, float m0, float m1, float v1) {
                float s2 = s * s, s3 = s2 * s;
                return (2.0 * s3 - 3.0 * s2 + 1.0) * v0 + (s3 - 2.0 * s2 + s) * m0 + (s3 - s2) * m1 + (-2.0 * s3 + 3.0 * s2) * v1;
            }
            float kcurveRidged(float t) {
                if (t <= 0.00724905916) return 0.000746440841;
                if (t < 0.268379867) return khermite((t - 0.00724905916) / 0.26113081, 0.000746440841, 0.0, 0.00797505304, -0.000739295036);
                if (t < 0.289745688) return khermite((t - 0.268379867) / 0.0213658214, -0.000739295036, 0.000652521849, 0.240945265, 0.416495025);
                if (t < 0.313458025) return khermite((t - 0.289745688) / 0.023712337, 0.416495025, 0.267407238, -0.410220236, 0.416779935);
                if (t < 0.386898786) return khermite((t - 0.313458025) / 0.0734407604, 0.416779935, -1.27051532, -0.0016246225, 0.00158712408);
                if (t < 0.420217991) return khermite((t - 0.386898786) / 0.033319205, 0.00158712408, -0.000737072027, 0.150789246, 0.143057227);
                if (t < 0.519818783) return khermite((t - 0.420217991) / 0.0996007919, 0.143057227, 0.450752914, 0.00380041287, 0.640726447);
                if (t < 0.99785614) return khermite((t - 0.519818783) / 0.478037357, 0.640726447, 0.0182402097, -0.0116770389, 0.655246794);
                return 0.655246794;
            }

            float kcurveMountains(float t) {
                if (t <= 0.0) return 0.0;
                if (t < 0.93288672) return khermite((t - 0.0) / 0.93288672, 0.0, 0.0, 1.54827273, 0.480846733);
                if (t < 1.0) return khermite((t - 0.93288672) / 0.0671132803, 0.480846733, 0.111385085, 0.201732069, 1.0);
                return 1.0;
            }

            float klerp4(float4 r, float p) {
                if (p <= r.x || p >= r.w) return 0.0;
                if (p < r.y) return (p - r.x) / (r.y - r.x);
                if (p <= r.z) return 1.0;
                return 1.0 - (p - r.z) / (r.w - r.z);
            }
            float kmap(float u, float v) {
                u = abs(u - floor(u)); v = abs(v - floor(v));
                float cx = u * 4096.0, cy = v * 2048.0;
                int x0 = int(floor(cx)), y0 = int(floor(cy)), x1 = int(ceil(cx)), y1 = int(ceil(cy));
                float mx = cx - float(x0), my = cy - float(y0);
                if (x1 == 4096) x1 = 0;
                if (y1 == 2048) y1 = 0;
                return lerp(lerp(TexelFetch(_KMap, int2(x0, y0), 0).r, TexelFetch(_KMap, int2(x1, y0), 0).r, mx),
                           lerp(TexelFetch(_KMap, int2(x0, y1), 0).r, TexelFetch(_KMap, int2(x1, y1), 0).r, mx), my);
            }
            float2 kdecalMap(float u, float v, int size, int row) {
                u = abs(u - floor(u)); v = abs(v - floor(v));
                float cx = u * float(size), cy = v * float(size);
                int x0 = int(floor(cx)), y0 = int(floor(cy)), x1 = int(ceil(cx)), y1 = int(ceil(cy));
                float mx = cx - float(x0), my = cy - float(y0);
                if (x1 == size) x1 = 0;
                if (y1 == size) y1 = 0;
                return lerp(lerp(TexelFetch(_KDecalMaps, int2(x0, row + y0), 0).rg, TexelFetch(_KDecalMaps, int2(x1, row + y0), 0).rg, mx),
                           lerp(TexelFetch(_KDecalMaps, int2(x0, row + y1), 0).rg, TexelFetch(_KDecalMaps, int2(x1, row + y1), 0).rg, mx), my);
            }
            float ksmooth(float u, float v, float s) {
                if (!(s > 0.0)) return 1.0;
                float r = 1.0 / s, m = 1.0 - s;
                return min(u < s ? u * r : (u > m ? (1.0 - u) * r : 1.0), v < s ? v * r : (v > m ? (1.0 - v) * r : 1.0));
            }
            // (the angle between two unit directions, from the chord: exact near nought, where acos of their dot is not in single precision)
            float kangle(float3 a, float3 b) { return 2.0 * asin(min(0.5 * length(a - b), 1.0)); }
            float kdecals(float3 d, float h) {
                if (_KDecals.x > 0.5) {  // PQSMod_MapDecalTangent 'IslandAirfield'
                    float3 pn = float3(0.310260147, -0.0263579395, -0.950286269);
                    if (kangle(d, pn) <= 0.00799998933) {
                        float u = (dot(float3(-0.023649931, 0.999092102, -0.0354331136), d) * 500.0 + 1.0) * 0.5, v = (dot(float3(-0.950357437, -0.0334676802, -0.30935514), d) * 500.0 + 1.0) * 0.5;
                        if (u >= 0.0 && u <= 1.0 && v >= 0.0 && v <= 1.0) {
                            float2 ha = kdecalMap(u, v, 256, 2048);
                            float sf = ksmooth(u, v, 0.200000003) * ha.y;
                            if (sf > 0.0 && ha.x > 0.0) h = lerp(h, 200.0 * ha.x / dot(d, pn) + -85.0, sf);
                        }
                    }
                }
                if (_KDecals.y > 0.5) {  // PQSMod_MapDecal 'KSC2'
                    float3 pn = float3(-0.780759037, 0.3515625, -0.516545296);
                    if (kangle(d, pn) <= 0.013333284) {
                        float u = (dot(float3(-0.22873807, -0.930125117, -0.287308633), d) * 300.0 + 1.0) * 0.5, v = (dot(float3(0.581458747, 0.106165305, -0.806619406), d) * 300.0 + 1.0) * 0.5;
                        if (u >= 0.0 && u <= 1.0 && v >= 0.0 && v <= 1.0) {
                            float2 ha = kdecalMap(u, v, 1024, 1024);
                            float sf = ksmooth(u, v, 0.100000001) * ha.y;
                            if (sf > 0.0) h = lerp(h, 400.0 + 100.0 * ha.x, sf);
                        }
                    }
                }
                if (_KFlats.x > 0.5) {  // PQSMod_FlattenArea 'Pyramids'
                    // (the game's angle from its centre, whose direction it holds not quite of length one: the arc cosine of the dot
                    // with it, here from the true angle and how much longer than one it is (_KFlats.z); none where that
                    // is not a number in the game)
                    float a = kangle(d, float3(-0.779567995, -0.113301879, -0.615984112));
                    a = a * a - 2.0 * _KFlats.z;
                    if (a >= 0.0) a = sqrt(a); else a = 1.0;
                    if (a < 0.00166666512) {
                        if (a < 0.000666666568) h = 1300.0;
                        else {
                            float t = (a - 0.000666666568) * 1000.00144, t2 = t * t, t3 = t2 * t;
                            h = 1300.0 * (2.0 * t3 - 3.0 * t2 + 1.0) + 0.0 * (t3 - 2.0 * t2 + t) + h * (-2.0 * t3 + 3.0 * t2) + 0.0 * (t3 - t2);
                        }
                    }
                }
                if (_KDecals.z > 0.5) {  // PQSMod_MapDecalTangent 'KSC'
                    float3 pn = float3(0.265546143, -0.00507413037, -0.964084804);
                    if (kangle(d, pn) <= 0.0499973961) {
                        float u = (dot(float3(-0.877150416, -0.416281343, -0.239410087), d) * 80.0 + 1.0) * 0.5, v = (dot(float3(0.400115728, -0.909221768, 0.114992619), d) * 80.0 + 1.0) * 0.5;
                        if (u >= 0.0 && u <= 1.0 && v >= 0.0 && v <= 1.0) {
                            float2 ha = kdecalMap(u, v, 1024, 0);
                            float sf = ksmooth(u, v, 0.0) * ha.y;
                            if (sf > 0.0) h = lerp(h, 70.0 * ha.x / dot(d, pn) + 0.0, sf);
                        }
                    }
                }
                if (_KFlats.y > 0.5) {  // PQSMod_FlattenArea 'Desert_Airfield'
                    // (the game's angle from its centre, whose direction it holds not quite of length one: the arc cosine of the dot
                    // with it, here from the true angle and how much longer than one it is (_KFlats.w); none where that
                    // is not a number in the game)
                    float a = kangle(d, float3(-0.804127606, -0.114243682, -0.583375672));
                    a = a * a - 2.0 * _KFlats.w;
                    if (a >= 0.0) a = sqrt(a); else a = 1.0;
                    if (a < 0.00749985938) {
                        if (a < 0.00333332099) h = 820.0;
                        else {
                            float t = (a - 0.00333332099) * 240.007389, t2 = t * t, t3 = t2 * t;
                            h = 820.0 * (2.0 * t3 - 3.0 * t2 + 1.0) + 0.0 * (t3 - 2.0 * t2 + t) + h * (-2.0 * t3 + 3.0 * t2) + 0.0 * (t3 - t2);
                        }
                    }
                }
                return h;
            }

            // (the height above the radius and the land colour of a unit direction in the PQS's frame)
            float kerbinGround(float3 d, out float4 colour) {
                float lat = atan2(d.y, length(d.xz)), lon = atan2(d.x, d.z);
                if (lon < -1.57079633) lon += 6.28318531;
                float sx = lon / 3.14159265 * 0.5, sy = lat / 3.14159265 + 0.5;
                float h = -1500.0 + 5000.0 * kmap(sx, sy);
                {
                    float t = clamp((h + 1985.0) / 6000.0, 0.0, 1.0);
                    float s = (ksimplex(15, d, 2.0, 0.100000001, 50.0) + 1.0) * 0.5;
                    if (s != 0.0) h += clamp(max(-0.699999988, kridged(d, 140.0, 2.5, 3, 1384047773, true)) * max(s, 0.0), -1.0, 1.0) * 750.0 * kcurveRidged(t);
                }
                h += (ksimplex(16, d, 8.0, 0.600000024, 24.0) + 1.0) * 0.5 * 485.0;
                {
                    float t = clamp((h + 1985.0 - 800.0) / 3800.0, 0.0, 1.0);
                    float s = (ksimplex(15, d, 4.0, 0.600000024, 32.0) + 1.0) * 0.5 * kcurveMountains(t);
                    if (s != 0.0) h += (clamp(kridged(d, 48.0, 4.0, 6, 1384047773, false) - kridged(d, 32.0, 4.0, 6, 2113370706, false), -1.0, 1.0) + 1.0) * 0.5 * 4000.0 * s;
                }
                h = kdecals(d, h);
                float vHeight = min(h / 3500.0 + 0.01 * ksimplex(17, d, 2.0, 0.600000024, 12.0), 1.0);
                float vLat = clamp(sy + 0.05 * ksimplex(18, d, 4.0, 0.600000024, 4.0), 0.0, 1.0);
                float vLon = clamp(sx + 0.05 * ksimplex(19, d, 4.0, 0.600000024, 4.0), 0.0, 1.0);
                float deltas[11];
                float total = 0.0, delta;
                // BaseBeach
                delta = klerp4(float4(-0.0500000007, 0.0, 0.00499999989, 0.0199999996), vHeight) * max(klerp4(float4(0.399999976, 0.399999976, 0.909999996, 0.909999996), vLat), klerp4(float4(0.0900000036, 0.0900000036, 0.600000024, 0.600000024), vLat)) * klerp4(float4(-1.0, -1.0, 2.0, 2.0), vLon);
                if (delta != 0.0) delta = (delta * (ksimplex(0, d, 4.0, 0.5, 2.0) + 1.0) * 0.5) * 1.0 + delta * 0.0;
                deltas[0] = delta; total += delta;
                // BaseLand
                delta = klerp4(float4(0.0, 0.00999999978, 0.699999988, 0.800000012), vHeight) * max(klerp4(float4(0.399999976, 0.399999976, 0.909999996, 0.909999996), vLat), klerp4(float4(0.0900000036, 0.0900000036, 0.600000024, 0.600000024), vLat)) * klerp4(float4(-1.0, -1.0, 2.0, 2.0), vLon);
                if (delta != 0.0) delta = (delta * (ksimplex(1, d, 8.0, 0.5, 6.0) + 1.0) * 0.5) * 1.0 + delta * 0.0;
                deltas[1] = delta; total += delta;
                // BaseMountains
                delta = klerp4(float4(0.200000003, 0.400000006, 2.0, 2.0), vHeight) * klerp4(float4(0.0, 0.0, 1.0, 1.0), vLat) * klerp4(float4(-1.0, -1.0, 2.0, 2.0), vLon);
                if (delta != 0.0) delta = (delta * (ksimplex(2, d, 4.0, 0.600000024, 2.0) + 1.0) * 0.5) * 0.7 + delta * 0.3;
                deltas[2] = delta; total += delta;
                // BaseSnow
                delta = klerp4(float4(0.600000024, 0.800000012, 25.0, 25.0), vHeight) * max(klerp4(float4(0.550000012, 0.599999994, 1.0, 1.0), vLat), klerp4(float4(0.0, 0.0, 0.400000006, 0.449999988), vLat)) * klerp4(float4(-1.0, -1.0, 2.0, 2.0), vLon);
                if (delta != 0.0) delta = (delta * (ksimplex(3, d, 4.0, 0.5, 1.0) + 1.0) * 0.5) * 0.0 + delta * 1.0;
                deltas[3] = delta; total += delta;
                // Tundra
                delta = klerp4(float4(0.0, 0.0500000007, 0.800000012, 1.0), vHeight) * max(klerp4(float4(0.699999988, 0.849999994, 2.0, 2.0), vLat), klerp4(float4(-1.0, -1.0, 0.150000006, 0.300000012), vLat)) * klerp4(float4(-1.0, -1.0, 2.0, 2.0), vLon);
                if (delta != 0.0) delta = (delta * (ksimplex(4, d, 4.0, 0.5, 6.0) + 1.0) * 0.5) * 1.0 + delta * 0.0;
                deltas[4] = delta; total += delta;
                // DesertGround
                delta = klerp4(float4(0.0, 0.00999999978, 0.600000024, 0.800000012), vHeight) * klerp4(float4(0.400000006, 0.449999988, 0.550000012, 0.600000024), vLat) * klerp4(float4(0.479999989, 0.550000012, 0.649999976, 0.699999988), vLon);
                if (delta != 0.0) delta = (delta * (ksimplex(5, d, 4.0, 0.600000024, 3.0) + 1.0) * 0.5) * 0.1 + delta * 0.9;
                deltas[5] = delta; total += delta;
                // DesertMountains
                delta = klerp4(float4(0.600000024, 0.800000012, 25.0, 25.0), vHeight) * klerp4(float4(0.400000006, 0.449999988, 0.550000012, 0.600000024), vLat) * klerp4(float4(0.449999988, 0.5, 0.649999976, 0.75), vLon);
                if (delta != 0.0) delta = (delta * (ksimplex(5, d, 4.0, 0.600000024, 1.0) + 1.0) * 0.5) * 0.5 + delta * 0.5;
                deltas[6] = delta; total += delta;
                // RockyGround
                delta = klerp4(float4(0.300000012, 0.5, 0.75, 0.800000012), vHeight) * klerp4(float4(0.0900000036, 0.0900000036, 0.910000026, 0.910000026), vLat) * klerp4(float4(-1.0, -1.0, 2.0, 2.0), vLon);
                if (delta != 0.0) delta = (delta * (ksimplex(5, d, 4.0, 0.600000024, 2.0) + 1.0) * 0.5) * 1.0 + delta * 0.0;
                deltas[7] = delta; total += delta;
                // IceCaps
                delta = klerp4(float4(-10.0, -10.0, 10.0, 10.0), vHeight) * max(klerp4(float4(0.909999996, 0.909999996, 2.0, 2.0), vLat), klerp4(float4(-1.0, -1.0, 0.0900000036, 0.0900000036), vLat)) * klerp4(float4(-1.0, -1.0, 2.0, 2.0), vLon);
                if (delta != 0.0) delta = (delta * (ksimplex(5, d, 4.0, 0.699999988, 5.0) + 1.0) * 0.5) * 0.0 + delta * 1.0;
                deltas[8] = delta; total += delta;
                // Ocean Bottom
                delta = klerp4(float4(-1.0, -1.0, -0.0500000007, 0.0), vHeight) * max(klerp4(float4(0.399999976, 0.399999976, 0.909999996, 0.909999996), vLat), klerp4(float4(0.0900000036, 0.0900000036, 0.600000024, 0.600000024), vLat)) * klerp4(float4(-1.0, -1.0, 2.0, 2.0), vLon);
                if (delta != 0.0) delta = (delta * (ksimplex(5, d, 4.0, 0.699999988, 5.0) + 1.0) * 0.5) * 0.0 + delta * 1.0;
                deltas[9] = delta; total += delta;
                // Savannah
                delta = klerp4(float4(0.0, 0.00999999978, 0.699999988, 0.800000012), vHeight) * klerp4(float4(0.300000012, 0.400000006, 0.400000006, 0.550000012), vLat) * klerp4(float4(0.0, 0.075000003, 0.100000001, 0.25), vLon);
                if (delta != 0.0) delta = (delta * (ksimplex(6, d, 4.0, 0.699999988, 5.0) + 1.0) * 0.5) * 0.2 + delta * 0.8;
                deltas[10] = delta; total += delta;

                colour = ((float4)(0.0));
                float apparent = 0.0;
                if (total != 0.0) {
                delta = deltas[0] / total;
                if (delta > 0.0) {
                    colour += lerp(float4(0.694000006, 0.630999982, 0.47299999, 1.0), float4(0.603999972, 0.582000017, 0.453999996, 1.0), clamp(0.5 * (ksimplex(7, d, 4.0, 0.5, 8.0) + 1.0) * 0.5, 0.0, 1.0)) * delta;
                }
                delta = deltas[1] / total;
                if (delta > 0.0) {
                    colour += lerp(float4(0.234999999, 0.275999993, 0.189999998, 1.0), float4(0.150999993, 0.201000005, 0.0850000009, 1.0), clamp(0.75 * (ksimplex(8, d, 3.0, 0.899999976, 14.0) + 1.0) * 0.5, 0.0, 1.0)) * delta;
                }
                delta = deltas[2] / total;
                if (delta > 0.0) {
                    colour += lerp(float4(0.142000005, 0.142000005, 0.142000005, 1.0), float4(0.149000004, 0.141000003, 0.128000006, 1.0), clamp(1.0 * (ksimplex(9, d, 4.0, 0.600000024, 12.0) + 1.0) * 0.5, 0.0, 1.0)) * delta;
                }
                delta = deltas[3] / total;
                if (delta > 0.0) {
                    colour += lerp(float4(0.925000012, 0.940999985, 0.953000009, 1.0), float4(0.728999972, 0.815999985, 0.866999984, 1.0), clamp(0.25 * (ksimplex(10, d, 4.0, 0.600000024, 18.0) + 1.0) * 0.5, 0.0, 1.0)) * delta;
                }
                delta = deltas[4] / total;
                if (delta > 0.0) {
                    colour += lerp(float4(0.333000004, 0.439999998, 0.296999991, 1.0), float4(0.349999994, 0.425000012, 0.344000012, 1.0), clamp(1.0 * (ksimplex(11, d, 4.0, 0.600000024, 34.0) + 1.0) * 0.5, 0.0, 1.0)) * delta;
                }
                delta = deltas[5] / total;
                if (delta > 0.0) {
                    colour += lerp(float4(0.64200002, 0.535000026, 0.411000013, 1.0), float4(0.582000017, 0.490999997, 0.416999996, 1.0), clamp(0.8 * (ksimplex(12, d, 2.0, 0.600000024, 14.0) + 1.0) * 0.5, 0.0, 1.0)) * delta;
                }
                delta = deltas[6] / total;
                if (delta > 0.0) {
                    apparent += delta * -0.8;
                        colour += lerp(float4(0.328000009, 0.298999995, 0.289999992, 1.0), float4(0.246000007, 0.229000002, 0.214000002, 1.0), clamp(0.5 * (ksimplex(12, d, 4.0, 0.600000024, 28.0) + 1.0) * 0.5, 0.0, 1.0)) * delta;
                }
                delta = deltas[7] / total;
                if (delta > 0.0) {
                    colour += lerp(float4(0.284000009, 0.240999997, 0.170000002, 1.0), float4(0.321999997, 0.301999986, 0.275000006, 1.0), clamp(0.5 * (ksimplex(13, d, 4.0, 0.600000024, 32.0) + 1.0) * 0.5, 0.0, 1.0)) * delta;
                }
                delta = deltas[8] / total;
                if (delta > 0.0) {
                    if (h < 20.0) h = delta * 20.0;
                        h += delta * 10.0;
                        apparent += delta * 100.0;
                        colour += lerp(float4(1.0, 1.0, 1.0, 1.0), float4(0.824000001, 0.936999977, 1.0, 1.0), clamp(1.0 * (ksimplex(13, d, 4.0, 0.600000024, 4.0) + 1.0) * 0.5, 0.0, 1.0)) * delta;
                }
                delta = deltas[9] / total;
                if (delta > 0.0) {
                    colour += lerp(float4(0.107000001, 0.178000003, 0.298999995, 1.0), float4(0.147, 0.296000004, 0.418000013, 1.0), clamp(0.5 * (ksimplex(13, d, 4.0, 0.600000024, 16.0) + 1.0) * 0.5, 0.0, 1.0)) * delta;
                }
                delta = deltas[10] / total;
                if (delta > 0.0) {
                    colour += lerp(float4(0.328999996, 0.234999999, 0.160999998, 1.0), float4(0.388000011, 0.31400001, 0.172999993, 1.0), clamp(1.0 * (ksimplex(14, d, 2.0, 0.600000024, 16.0) + 1.0) * 0.5, 0.0, 1.0)) * delta;
                }

                }
                // (how high the place looks: what the ground's shader lays its textures by)
                colour.a = clamp(vHeight + apparent, 0.0, 1.0);
                return h;
            }

            float4 frag(v2f IN) : SV_Target
            {
                float4 result = float4(0.0, 0.0, 0.0, 0.0);
                int2 c = ((int2)(IN.pos.xy));
                // (the picture's points beyond those drawn this frame, round or out, not worked out)
                if (c.x >= int(_FGPush.y + 0.5) || c.y >= int(_FGRound.w + 0.5)) { result = ((float4)(0.0)); return result; }
                float arc = min(_FGNorth.w * exp(_FGEast.w * float(c.y)), _FGRound.z);
                float az = _FGRound.x + _FGRound.y * float(c.x);
                float3 d = normalize(_FGUp.xyz * cos(arc) + (_FGNorth.xyz * cos(az) + _FGEast.xyz * sin(az)) * sin(arc));
                float4 colour;
                float h = kerbinGround(d, colour);
                // (the land colour packed eight bits a part into one number, exactly held by a float to 2^24; and how high it looks, for
                // the ground's shader's bands)
                result = float4(h, dot(floor(clamp(colour.rgb, 0.0, 1.0) * 255.0 + 0.5), float3(65536.0, 256.0, 1.0)), colour.a, 1.0);
                return result;
            }
            ENDCG
        }
    }
}
