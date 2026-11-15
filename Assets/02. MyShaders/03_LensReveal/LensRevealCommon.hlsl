// =====================================================================
//  LensRevealCommon.hlsl — RevealLens / CloakedTarget 가 함께 쓰는 함수
//
//  두 셰이더는 "스텐실 버퍼"로 대화한다.
//   1) RevealLens 가 먼저 그려지면서, 렌즈가 덮은 화면 픽셀의 스텐실 값을 _StencilRef 로 바꿔 둔다.
//   2) CloakedTarget 의 투명화 패스는 스텐실이 _StencilRef 가 "아닌" 곳(렌즈 밖)에만 그려진다.
//   3) CloakedTarget 의 실루엣 패스는 스텐실이 _StencilRef "인" 곳(렌즈 안)에만 그려진다.
//  그래서 맨눈에는 일렁임만, 렌즈 안에서는 실루엣만 보인다.
//  두 머티리얼의 _StencilRef 는 같은 값이어야 한다.
// =====================================================================
#ifndef MYSHADERS_LENSREVEAL_COMMON_INCLUDED
#define MYSHADERS_LENSREVEAL_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

// ---- 노이즈 (갤러리 클로킹 투명화의 값 노이즈) ---------------------------
float cloakHash(float3 p)
{
    p = frac(p * 0.1031);
    p = p + dot(p, p.zyx + 31.32);
    return frac((p.x + p.y) * p.z);
}

float cloakValueNoise(float3 p)
{
    float3 cell = floor(p);
    float3 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float x00 = lerp(cloakHash(cell + float3(0, 0, 0)), cloakHash(cell + float3(1, 0, 0)), f.x);
    float x10 = lerp(cloakHash(cell + float3(0, 1, 0)), cloakHash(cell + float3(1, 1, 0)), f.x);
    float x01 = lerp(cloakHash(cell + float3(0, 0, 1)), cloakHash(cell + float3(1, 0, 1)), f.x);
    float x11 = lerp(cloakHash(cell + float3(0, 1, 1)), cloakHash(cell + float3(1, 1, 1)), f.x);
    return lerp(lerp(x00, x10, f.y), lerp(x01, x11, f.y), f.z);
}

float cloakNoise(float3 p)
{
    float n = cloakValueNoise(p) * 0.7 + cloakValueNoise(p * 2.0 + float3(11.7, 0.0, 7.9)) * 0.3;
    return saturate((n - 0.2) / 0.6);
}

// ---- 화면 / 깊이 도우미 ------------------------------------------------
// 화면 uv 에 있는 불투명 장면의 "눈 깊이"(카메라에서 앞쪽으로 몇 m)
float SceneEyeDepth(float2 screenUV)
{
    return LinearEyeDepth(SampleSceneDepth(screenUV), _ZBufferParams);
}

// 이 픽셀(월드 위치)의 눈 깊이
float SelfEyeDepth(float3 positionWS)
{
    return -TransformWorldToView(positionWS).z;
}

#endif
