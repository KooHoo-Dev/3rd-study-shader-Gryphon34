// =====================================================================
//  HoloOrb — 안에 입체 방이 들어 있는 홀로그램 구슬 (URP 17, HLSL)
//  shader-gallery 「인테리어 매핑」 + 「홀로그램」 응용
//  효과 본체는 HoloOrbCore.hlsl, 이 파일은 프로퍼티 / 패스 / SRP Batcher 만 맡는다.
// =====================================================================
Shader "MyShaders/HoloOrb"
{
    Properties
    {
        [Header(Room Interior Mapping)]
        _RoomSize       ("방 상자 크기 (반지름, 오브젝트 단위)", Range(0.1, 1)) = 0.4
        _RoomSpin       ("방 회전 속도 (rad/s)", Range(-2, 2)) = 0.3
        _WallColor      ("벽 색", Color) = (0.85, 0.78, 0.66, 1)
        _FloorColor     ("바닥 색", Color) = (0.55, 0.42, 0.32, 1)
        _FloorTiles     ("바닥 타일 수", Range(1, 16)) = 6
        _WallPanels     ("벽 판자 수", Range(1, 16)) = 5
        [HDR] _WindowColor ("창밖 빛", Color) = (0.55, 0.75, 1.2, 1)
        [HDR] _LampColor   ("천장 등 색", Color) = (1, 0.78, 0.47, 1)
        _LampIntensity  ("등 밝기", Range(0, 5)) = 1.6
        _LampFalloff    ("등빛 퍼짐 (클수록 좁음)", Range(0.1, 10)) = 2
        _RoomAmbient    ("방 기본 밝기", Range(0, 1)) = 0.15
        _VoidColor      ("방 바깥 빈 공간 색", Color) = (0.02, 0.05, 0.08, 1)

        [Header(Custom Room Cubemap)]
        [Toggle(_ROOMCUBE_ON)] _UseRoomCube ("큐브맵으로 방 그리기", Float) = 0
        [NoScaleOffset] _RoomCube ("방 큐브맵", Cube) = "grey" {}
        _CubeExposure   ("큐브맵 밝기", Range(0, 4)) = 1

        [Header(Hologram)]
        [HDR] _HoloColor ("홀로그램 색", Color) = (0.24, 0.86, 1, 1)
        _HoloTint       ("홀로그램 색 입히기 (0 원래색, 1 단색)", Range(0, 1)) = 0.6
        _RimPower       ("테두리 좁히기", Range(0.5, 6)) = 2.5
        _RimStrength    ("테두리 밝기", Range(0, 4)) = 1.5
        _LineSpacing    ("스캔라인 간격 (m)", Range(0.02, 0.3)) = 0.06
        _ScanSpeed      ("스캔라인 속도 (m/s)", Range(-1, 1)) = 0.2
        _ScanStrength   ("스캔라인 세기", Range(0, 1)) = 0.6
        _GlitchStrength ("글리치 세기", Range(0, 1)) = 0.4
        _Flicker        ("깜빡임 세기", Range(0, 1)) = 0.3
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry" "RenderPipeline" = "UniversalPipeline" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        // 텍스처 선언은 CBUFFER 밖
        TEXTURECUBE(_RoomCube);
        SAMPLER(sampler_RoomCube);

        // SRP Batcher 호환: 머티리얼 값은 모두 이 안에
        CBUFFER_START(UnityPerMaterial)
            float  _RoomSize;
            float  _RoomSpin;
            float4 _WallColor;
            float4 _FloorColor;
            float  _FloorTiles;
            float  _WallPanels;
            float4 _WindowColor;
            float4 _LampColor;
            float  _LampIntensity;
            float  _LampFalloff;
            float  _RoomAmbient;
            float4 _VoidColor;
            float  _CubeExposure;
            float4 _HoloColor;
            float  _HoloTint;
            float  _RimPower;
            float  _RimStrength;
            float  _LineSpacing;
            float  _ScanSpeed;
            float  _ScanStrength;
            float  _GlitchStrength;
            float  _Flicker;
        CBUFFER_END

        #include "HoloOrbCore.hlsl"

        struct Attributes
        {
            float4 positionOS : POSITION;
            float3 normalOS   : NORMAL;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float3 positionOS : TEXCOORD0;   // 글리치로 밀린 뒤의 위치
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
            float3 p = HoloOrbVertex(v.positionOS.xyz, _Time.y);
            o.positionOS = p;
            o.positionWS = TransformObjectToWorld(p);
            o.positionCS = TransformWorldToHClip(o.positionWS);
            o.normalWS   = TransformObjectToWorldNormal(v.normalOS);
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
            #pragma shader_feature_local _ROOMCUBE_ON

            float4 frag(Varyings v) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(v);

                OrbInput i;
                i.positionOS = v.positionOS;
                i.positionWS = v.positionWS;
                i.normalWS   = normalize(v.normalWS);
                i.viewWS     = GetWorldSpaceNormalizeViewDir(v.positionWS);
                // 카메라 위치를 오브젝트 공간으로 옮긴다. 오브가 돌거나 늘어나도 방이 같이 따라간다.
                i.cameraPosOS = TransformWorldToObject(GetCameraPositionWS());
                // 직교 카메라는 시선이 모두 정면 축과 나란하므로 이 점에서 정면 축만큼 물러난 점을 카메라로 삼는다 (갤러리와 동일)
                if (unity_OrthoParams.w > 0.5)
                    i.cameraPosOS = v.positionOS - TransformWorldToObjectDir(GetViewForwardDir(), false);
                i.time = _Time.y;

                return float4(HoloOrbColor(i), 1.0);
            }
            ENDHLSL
        }

        // 깊이 텍스처 / 깊이 프리패스용
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

        // SSAO 등 노멀을 쓰는 기능용 (이 프로젝트 PC 렌더러는 SSAO 를 쓴다)
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
