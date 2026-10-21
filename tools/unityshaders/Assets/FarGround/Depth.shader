// FarGround/Depth: made from tools/shaderpack/fargrounddepth.glsl by tools/unityshaders/port.py. Do not edit: edit the GLSL and run that again.
Shader "FarGround/Depth"
{
    Properties
    {

    }
    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Pass
        {
            Blend Zero One
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
            Texture2D _FGPoints; SamplerState sampler_FGPoints;

            struct v2f
            {
                float4 pos : SV_POSITION;
            };

            // Far Ground's rings again, for the camera's depth picture only (src/FarGround): drawn into it just after the
            // game has made it (CameraEvent.AfterDepthTexture), as far off as the rings stand (fargrounddraw.glsl, whose placing this is). The
            // game makes that picture in a pass of its own, from the things it draws itself: what a command buffer draws is not in it, and
            // Scatterer, which lays the air over the ground by that picture, took the far ground's pixels for sky and laid no air over them
            // (the main chat, 2026-10-18: "a very dark olive with no haze", where the game's own ground there is hazy blue-green). The colour
            // is left as it is: only how far off is written, the nearer kept.

            v2f vert(float3 in_POSITION0 : POSITION)
            {
                v2f OUT = (v2f)0;
                int k = int(in_POSITION0.x + 0.5), ri = int(in_POSITION0.y + 0.5);
                int around = int(_FGPush.y + 0.5), rings = int(_FGRound.w + 0.5);
                if (ri >= rings || k >= around) { OUT.pos = float4(0.0, 0.0, _FGPush.w, 1.0); return OUT; }
                float4 t = TexelFetch(_FGPoints, int2(k, ri), 0);
                float arc = min(_FGNorth.w * exp(_FGEast.w * float(ri)), _FGRound.z);
                float az = _FGRound.x + _FGRound.y * float(k);
                float3 p = normalize(_FGUp.xyz * cos(arc) + (_FGNorth.xyz * cos(az) + _FGEast.xyz * sin(az)) * sin(arc)) * (_FGCam.w + t.r);
                float3 rel = p - _FGCam.xyz;
                // (placed as fargrounddraw.glsl places them, sum for sum)
                float howFar = length(rel);
                float push = min((_FGPush.x - 1.0) * howFar, _FGPush.z) * (1.0 - smoothstep(0.85 * _FGCut.w, _FGCut.w, length(normalize(p) - _FGCut.xyz)));
                float4 v = float4(rel * (1.0 + push / max(howFar, 1.0)), 1.0);
                OUT.pos = float4(dot(_FGRow0, v), dot(_FGRow1, v) * _ProjectionParams.x, dot(_FGRow2, v), dot(_FGRow3, v));
                return OUT;
            }

            float4 frag(v2f IN) : SV_Target
            {
                float4 result = float4(0.0, 0.0, 0.0, 0.0);
                result = ((float4)(0.0));
                return result;
            }
            ENDCG
        }
    }
}
