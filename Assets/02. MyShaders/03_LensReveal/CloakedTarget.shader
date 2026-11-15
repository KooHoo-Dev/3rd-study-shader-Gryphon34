// =====================================================================
//  CloakedTarget — 맨눈엔 투명, 렌즈로 보면 실루엣이 보이는 적 (URP 17, HLSL)
//  shader-gallery 「클로킹 투명화」 + 「가려진 실루엣」(실루엣 색칠 방식) 응용, 스텐실로 RevealLens 와 연결 (직접 추가)
//
//  패스 1  Cloak      : 렌즈 밖(스텐실 ≠ _StencilRef)에서만. 몸 뒤 장면을 법선 방향 + 노이즈로 휘어 그린다.
//                       → 몸은 안 보이고 배경이 유리처럼 일렁인다. 윤곽에 프레넬 테두리를 살짝.
//  패스 2  Silhouette : 렌즈 안(스텐실 = _StencilRef)에서만. 단색 + 프레넬 테두리 실루엣으로 그린다.
//                       깊이 검사는 보통대로(ZTest LEqual) 해서 벽에 가려진 부분은 렌즈로 봐도 안 보인다.
//
//  배경을 휘려면 불투명 장면 텍스처가 필요하므로 Queue 는 Transparent (불투명이 다 그려진 뒤).
//  RevealLens(Transparent-50)가 먼저 그려져 스텐실을 써 두어야 한다.
// =====================================================================
Shader "MyShaders/CloakedTarget"
{
    Properties
    {
        [Header(Stencil)]
        [IntRange] _StencilRef ("스텐실 번호 (RevealLens 와 같게)", Range(1, 255)) = 16

        [Header(Cloak)]
        _BaseColor      ("몸 색 (투명화 0 일 때)", Color) = (0.6, 0.62, 0.68, 1)
        _Cloak          ("투명화 정도", Range(0, 1)) = 1
        _Refraction     ("굴절 세기", Range(0, 0.2)) = 0.05
        _NoiseScale     ("일렁임 무늬 크기", Range(0.5, 20)) = 5
        _ShimmerSpeed   ("일렁임 속도", Range(0, 5)) = 1.2
        [HDR] _RimColor ("투명화 테두리 색", Color) = (0.7, 0.85, 1, 1)
        _RimPower       ("테두리 좁히기", Range(0.5, 8)) = 4
        _RimStrength    ("테두리 세기", Range(0, 2)) = 0.35

        [Header(Silhouette in Lens)]
        [HDR] _SilhouetteColor ("실루엣 색", Color) = (1, 0.45, 0.1, 1)
        _Opacity        ("실루엣 안쪽 불투명도", Range(0, 1)) = 0.45
        _RimWidth       ("실루엣 테두리 폭", Range(0.01, 1)) = 0.35
        _PulseSpeed     ("맥박 속도", Range(0, 10)) = 3
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" "RenderPipeline" = "UniversalPipeline" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "LensRevealCommon.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float  _StencilRef;
            float4 _BaseColor;
            float  _Cloak;
            float  _Refraction;
            float  _NoiseScale;
            float  _ShimmerSpeed;
            float4 _RimColor;
            float  _RimPower;
            float  _RimStrength;
            float4 _SilhouetteColor;
            float  _Opacity;
            float  _RimWidth;
            float  _PulseSpeed;
        CBUFFER_END

        struct Attributes
        {
            float4 positionOS : POSITION;
            float3 normalOS   : NORMAL;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float3 positionOS : TEXCOORD0;
            float3 positionWS : TEXCOORD1;
            float3 normalWS   : TEXCOORD2;
            UNITY_VERTEX_INPUT_INSTANCE_ID
            UNITY_VERTEX_OUTPUT_STEREO
        };

        Varyings vert(Attributes v)
        {
            Varyings o;
            UNITY_SETUP_INSTANCE_ID(v);
            UNITY_TRANSFER_INSTANCE_ID(v, o);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
            o.positionOS = v.positionOS.xyz;
            o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
            o.positionCS = TransformWorldToHClip(o.positionWS);
            o.normalWS   = TransformObjectToWorldNormal(v.normalOS);
            return o;
        }
        ENDHLSL

        // ---------------- 패스 1: 투명화 (렌즈 밖) ----------------
        Pass
        {
            Name "Cloak"
            Tags { "LightMode" = "UniversalForwardOnly" }

            Stencil
            {
                Ref [_StencilRef]
                Comp NotEqual       // 렌즈가 덮은 곳에는 그리지 않는다
            }
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment fragCloak
            #pragma multi_compile_instancing

            float4 fragCloak(Varyings v) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(v);
                float3 n = normalize(v.normalWS);
                float3 viewWS = GetWorldSpaceNormalizeViewDir(v.positionWS);
                float2 screenUV = GetNormalizedScreenSpaceUV(v.positionCS);

                // 1. 화면에서 미는 방향: 월드 법선을 카메라의 오른쪽/위 축에 내린다.
                //    법선 반대쪽(가운데 쪽)을 읽으면 몸 뒤 장면이 돋보기처럼 살짝 커져 보인다.
                float3 camRight = UNITY_MATRIX_V[0].xyz;
                float3 camUp    = UNITY_MATRIX_V[1].xyz;
                float2 normalSS = float2(dot(n, camRight), dot(n, camUp));

                // 2. 흐르는 노이즈로 일렁임을 더한다 (몸에 붙도록 오브젝트 공간 위치로 읽음)
                float3 sp = v.positionOS * _NoiseScale - float3(0.0, _Time.y * _ShimmerSpeed, 0.0);
                float2 ripple = float2(cloakNoise(sp), cloakNoise(sp + float3(31.4, 0.0, 17.7))) * 2.0 - 1.0;
                float2 shift = (-normalSS + ripple * 0.35) * _Refraction;
                shift *= float2(_ScreenParams.y / _ScreenParams.x, 1.0);   // 가로세로 비율 보정

                // 3. 앞 물체 끌림 방지: 밀린 자리의 장면이 몸보다 앞에 있으면 밀지 않은 자리를 읽는다.
                float2 uv = saturate(screenUV + shift);
                float selfEye = SelfEyeDepth(v.positionWS);
                uv = lerp(uv, screenUV, step(SceneEyeDepth(uv), selfEye));
                float3 scene = SampleSceneColor(uv);

                // 4. 프레넬 테두리 + 투명화 정도로 몸과 섞기
                float facing = saturate(dot(n, viewWS));
                float rim = pow(max(1.0 - facing, 0.0001), _RimPower) * _RimStrength;
                Light light = GetMainLight();
                float3 lit = _BaseColor.rgb * (light.color * saturate(dot(n, light.direction)) + SampleSH(n));
                float3 color = lerp(lit, scene, _Cloak) + _RimColor.rgb * rim * _Cloak;
                return float4(color, 1.0);
            }
            ENDHLSL
        }

        // ---------------- 패스 2: 실루엣 (렌즈 안) ----------------
        // 같은 LightMode 패스가 둘이면 URP 는 첫 번째만 그리므로 SRPDefaultUnlit 를 쓴다.
        Pass
        {
            Name "Silhouette"
            Tags { "LightMode" = "SRPDefaultUnlit" }

            Stencil
            {
                Ref [_StencilRef]
                Comp Equal          // 렌즈가 덮은 곳에만
            }
            ZTest LEqual            // 보통 깊이 검사: 벽에 가려진 부분은 그리지 않는다
            ZWrite Off
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment fragSilhouette
            #pragma multi_compile_instancing

            float4 fragSilhouette(Varyings v) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(v);
                float3 n = normalize(v.normalWS);
                float3 viewWS = GetWorldSpaceNormalizeViewDir(v.positionWS);

                // 1. 테두리 (갤러리 가려진 실루엣): 시선과 법선 사이 각의 sin 으로 둥근 몸에서 고르게 커진다.
                float facing = saturate(dot(n, viewWS));
                float side = sqrt(saturate(1.0 - facing * facing));
                float edge = smoothstep(1.0 - _RimWidth, 1.0, side);

                // 2. 안쪽은 _Opacity 만큼, 윤곽은 진하게
                float alpha = lerp(_Opacity, 1.0, edge);
                float3 color = lerp(_SilhouetteColor.rgb, float3(1, 1, 1), edge * 0.4);

                // 3. 맥박: 살아 있는 것처럼 천천히 밝아졌다 어두워진다
                alpha *= 0.8 + 0.2 * sin(_Time.y * _PulseSpeed);
                return float4(color, saturate(alpha));
            }
            ENDHLSL
        }
    }
    FallBack Off
}
