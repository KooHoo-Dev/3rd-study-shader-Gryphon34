// =====================================================================
//  WinterToon — 위쪽에 눈이 쌓이는 겨울 툰 오브젝트 (URP 17, HLSL)
//  shader-gallery 「램프 툰 조명」 + 「젖음과 눈 쌓임」 + 「프레넬 림 빛」 응용
//  효과 본체는 WinterToonCore.hlsl, 이 파일은 프로퍼티 / 조명 / 패스 / SRP Batcher 만 맡는다.
// =====================================================================
Shader "MyShaders/WinterToon"
{
    Properties
    {
        [Header(Toon)]
        _BaseMap        ("기본 텍스처", 2D) = "white" {}
        _BaseColor      ("기본 색", Color) = (0.86, 0.36, 0.3, 1)
        _ShadeColor     ("그늘 색 (곱하기)", Color) = (0.42, 0.45, 0.72, 1)
        _Bands          ("음영 단계 수", Range(2, 5)) = 3
        _Softness       ("단계 경계 부드러움", Range(0, 0.5)) = 0.05
        _ShadeShift     ("그늘 넓이", Range(-0.25, 0.8)) = 0

        [Header(Snow)]
        _SnowColor      ("눈 색", Color) = (0.97, 0.98, 1, 1)
        _SnowShadeColor ("눈 그늘 색 (곱하기)", Color) = (0.62, 0.74, 0.95, 1)
        _Coverage       ("눈 덮인 정도", Range(0, 1)) = 0.55
        _SnowSoftness   ("눈 경계 부드러움", Range(0.001, 0.3)) = 0.03
        _NoiseScale     ("눈 경계 노이즈 크기", Range(0.5, 20)) = 6
        _SnowHeight     ("눈 두께 (정점 밀기)", Range(0, 0.1)) = 0.02
        _Glint          ("눈 반짝임", Range(0, 8)) = 3

        [Header(Rim)]
        [HDR] _RimColor ("림 색", Color) = (0.6, 0.85, 1, 1)
        _RimPower       ("림 좁히기", Range(0.5, 8)) = 3
        _RimIntensity   ("림 세기", Range(0, 3)) = 0.8
        _RimHardness    ("림 딱딱함 (0 부드럽게, 1 툰)", Range(0, 1)) = 0.85
        _RimBacklight   ("빛 반대편에만 (역광)", Range(0, 1)) = 0.7
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry" "RenderPipeline" = "UniversalPipeline" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            float4 _BaseColor;
            float4 _ShadeColor;
            float  _Bands;
            float  _Softness;
            float  _ShadeShift;
            float4 _SnowColor;
            float4 _SnowShadeColor;
            float  _Coverage;
            float  _SnowSoftness;
            float  _NoiseScale;
            float  _SnowHeight;
            float  _Glint;
            float4 _RimColor;
            float  _RimPower;
            float  _RimIntensity;
            float  _RimHardness;
            float  _RimBacklight;
        CBUFFER_END

        #include "WinterToonCore.hlsl"

        struct Attributes
        {
            float4 positionOS : POSITION;
            float3 normalOS   : NORMAL;
            float2 uv         : TEXCOORD0;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float2 uv         : TEXCOORD0;
            float3 positionOS : TEXCOORD1;   // 밀기 전 위치 (노이즈가 눈 두께에 따라 흔들리지 않게)
            float3 positionWS : TEXCOORD2;
            float3 normalWS   : TEXCOORD3;
            UNITY_VERTEX_INPUT_INSTANCE_ID
            UNITY_VERTEX_OUTPUT_STEREO
        };

        Varyings vert(Attributes v)
        {
            Varyings o;
            UNITY_SETUP_INSTANCE_ID(v);
            UNITY_TRANSFER_INSTANCE_ID(v, o);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
            float3 p = WinterToonVertex(v.positionOS.xyz, v.normalOS);
            o.positionOS = v.positionOS.xyz;
            o.positionWS = TransformObjectToWorld(p);
            o.positionCS = TransformWorldToHClip(o.positionWS);
            o.normalWS   = TransformObjectToWorldNormal(v.normalOS);
            o.uv         = TRANSFORM_TEX(v.uv, _BaseMap);
            return o;
        }
        ENDHLSL

        Pass
        {
            Name "Forward"
            Tags { "LightMode" = "UniversalForwardOnly" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 frag(Varyings v) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(v);

                Light light = GetMainLight(TransformWorldToShadowCoord(v.positionWS), v.positionWS, half4(1, 1, 1, 1));

                WinterInput i;
                i.uv         = v.uv;
                i.positionOS = v.positionOS;
                i.normalWS   = normalize(v.normalWS);
                i.viewWS     = GetWorldSpaceNormalizeViewDir(v.positionWS);
                i.lightDirWS = light.direction;
                i.lightColor = light.color * light.shadowAttenuation;   // 받는 그림자도 같은 계단으로 끊긴다

                float3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, v.uv).rgb * _BaseColor.rgb;
                return float4(WinterToonColor(i, albedo), 1.0);
            }
            ENDHLSL
        }

        // 그림자도 눈 두께만큼 부푼 모양으로 드리운다
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex vertShadow
            #pragma fragment fragShadow
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            float3 _LightDirection;
            float3 _LightPosition;

            Varyings vertShadow(Attributes v)
            {
                Varyings o = vert(v);
                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDir = normalize(_LightPosition - o.positionWS);
                #else
                    float3 lightDir = _LightDirection;
                #endif
                float4 cs = TransformWorldToHClip(ApplyShadowBias(o.positionWS, normalize(o.normalWS), lightDir));
                #if UNITY_REVERSED_Z
                    cs.z = min(cs.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    cs.z = max(cs.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                o.positionCS = cs;
                return o;
            }

            half4 fragShadow(Varyings v) : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment fragDepth
            #pragma multi_compile_instancing

            half fragDepth(Varyings v) : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment fragNormals
            #pragma multi_compile_instancing

            half4 fragNormals(Varyings v) : SV_Target { return half4(normalize(v.normalWS), 0.0); }
            ENDHLSL
        }
    }
    FallBack Off
}
