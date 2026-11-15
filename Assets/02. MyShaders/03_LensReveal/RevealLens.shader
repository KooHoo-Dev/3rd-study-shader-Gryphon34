// =====================================================================
//  RevealLens — 투명화된 적을 드러내는 "특수 렌즈" (URP 17, HLSL)
//  렌즈 + 투명화 적(CloakedTarget) 세트 중 렌즈 쪽.
//
//  원리
//   1) 스텐실 쓰기: 렌즈가 덮은 픽셀의 스텐실 값을 _StencilRef 로 바꾼다 (Comp Always, Pass Replace).
//      → CloakedTarget 이 이 값을 보고 렌즈 안/밖을 구분한다.
//   2) 렌즈 화면: 불투명 장면 텍스처(_CameraOpaqueTexture)를 읽어 흑백으로 바꾼 뒤 렌즈 색을 입히고
//      스캔라인·가장자리 어둡게(비네트)·테두리를 더해 "탐지 스코프"처럼 보이게 한다.
//   3) Quad 에 쓰면 UV 로 원 모양을 잘라(clip) 둥근 렌즈가 된다. 잘린 픽셀은 스텐실도 쓰지 않는다.
//
//  CloakedTarget(Queue Transparent) 보다 먼저 그려져야 하므로 Queue 를 Transparent-50 으로 둔다.
// =====================================================================
Shader "MyShaders/RevealLens"
{
    Properties
    {
        [Header(Stencil)]
        [IntRange] _StencilRef ("스텐실 번호 (CloakedTarget 과 같게)", Range(1, 255)) = 16

        [Header(Shape)]
        [Enum(Circle,0, FullMesh,1)] _Shape ("모양 (Circle 은 Quad 용)", Float) = 0
        _RingWidth      ("테두리 두께", Range(0, 0.2)) = 0.04
        _RingColor      ("테두리 색", Color) = (0.12, 0.1, 0.08, 1)

        [Header(Lens View)]
        [HDR] _LensTint ("렌즈 색", Color) = (0.35, 1, 0.75, 1)
        _Desaturate     ("흑백 정도", Range(0, 1)) = 0.9
        _Brightness     ("밝기", Range(0, 3)) = 1.1
        _ScanDensity    ("스캔라인 밀도 (화면 줄 수)", Range(50, 800)) = 300
        _ScanStrength   ("스캔라인 세기", Range(0, 1)) = 0.25
        _Vignette       ("가장자리 어둡게", Range(0, 2)) = 0.8
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent-50" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "Lens"
            Tags { "LightMode" = "UniversalForwardOnly" }

            Stencil
            {
                Ref [_StencilRef]
                Comp Always
                Pass Replace       // 렌즈가 그려진 픽셀 = 스텐실에 표시
            }
            ZWrite Off
            Cull Off               // Quad 를 뒤에서 봐도 렌즈

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "LensRevealCommon.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float  _StencilRef;
                float  _Shape;
                float  _RingWidth;
                float4 _RingColor;
                float4 _LensTint;
                float  _Desaturate;
                float  _Brightness;
                float  _ScanDensity;
                float  _ScanStrength;
                float  _Vignette;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = v.uv;
                return o;
            }

            float4 frag(Varyings i) : SV_Target
            {
                // 1. 모양: UV 가운데에서의 거리. Circle 이면 원 밖을 버린다 (스텐실도 안 써진다).
                float r = length(i.uv - 0.5) * 2.0;                 // 가운데 0, 가장자리 1
                if (_Shape < 0.5) clip(1.0 - r);
                else r = 0.0;                                        // FullMesh 는 테두리·비네트 없음

                // 2. 렌즈 너머 장면: 불투명 장면 텍스처를 그대로 읽어 흑백 + 렌즈 색
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);
                float3 scene = SampleSceneColor(screenUV);
                float lum = dot(scene, float3(0.299, 0.587, 0.114));
                float3 view = lerp(scene, lum.xxx, _Desaturate) * _LensTint.rgb * _Brightness;

                // 3. 스캔라인 (화면 높이 기준 가로줄)
                float scan = 0.5 + 0.5 * sin(screenUV.y * _ScanDensity * 6.2831853);
                view *= 1.0 - _ScanStrength * scan;

                // 4. 비네트 + 테두리
                view *= saturate(1.0 - pow(r, 4.0) * _Vignette);
                float ring = smoothstep(1.0 - _RingWidth - 0.01, 1.0 - _RingWidth, r) * step(_Shape, 0.5);
                view = lerp(view, _RingColor.rgb, ring);

                return float4(view, 1.0);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
