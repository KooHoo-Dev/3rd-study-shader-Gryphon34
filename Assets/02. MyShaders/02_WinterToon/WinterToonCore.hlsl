// =====================================================================
//  WinterToonCore.hlsl — WinterToon 효과 본체
//  shader-gallery 「램프 툰 조명」 + 「젖음과 눈 쌓임」 + 「프레넬 림 빛」 응용
//
//   1) 툰:  dot(N, L) 을 _Bands 개의 계단으로 끊고, 그 값으로 그늘 색 ↔ 빛 색 사이를 고른다.
//   2) 눈:  월드 법선 y(위를 보는 정도)에 노이즈를 더해 위쪽만 눈으로 덮는다.
//           [직접 추가] 눈도 같은 계단 음영을 써서 만화풍 눈이 되고, 눈 덮인 정점을 법선 방향으로 밀어
//           눈이 "두껍게 쌓인" 것처럼 부풀린다.
//   3) 림:  1 - dot(N, V) 를 거듭제곱해 윤곽만 밝힌다.
//           [직접 추가] smoothstep 으로 끊어 툰 스타일의 딱 떨어지는 림으로 만들고, 빛 반대편 윤곽에만 둔다(역광).
// =====================================================================
#ifndef MYSHADERS_WINTERTOON_CORE_INCLUDED
#define MYSHADERS_WINTERTOON_CORE_INCLUDED

#define SURFACE_NOISE_AMOUNT 0.6     // 노이즈가 눈 경계를 흔드는 폭 (갤러리 값)
#define SURFACE_GLINT_CELLS 90.0     // 눈 반짝임 알갱이 촘촘함 (갤러리 값)

// ---- 노이즈 (갤러리 젖음과 눈 쌓임) -------------------------------------
float surfaceHash(float3 p)
{
    p = frac(p * 0.1031);
    p = p + dot(p, p.zyx + 31.32);
    return frac((p.x + p.y) * p.z);
}

float surfaceValueNoise(float3 p)
{
    float3 cell = floor(p);
    float3 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float x00 = lerp(surfaceHash(cell + float3(0, 0, 0)), surfaceHash(cell + float3(1, 0, 0)), f.x);
    float x10 = lerp(surfaceHash(cell + float3(0, 1, 0)), surfaceHash(cell + float3(1, 1, 0)), f.x);
    float x01 = lerp(surfaceHash(cell + float3(0, 0, 1)), surfaceHash(cell + float3(1, 0, 1)), f.x);
    float x11 = lerp(surfaceHash(cell + float3(0, 1, 1)), surfaceHash(cell + float3(1, 1, 1)), f.x);
    return lerp(lerp(x00, x10, f.y), lerp(x01, x11, f.y), f.z);
}

float surfaceNoise(float3 p)
{
    float n = surfaceValueNoise(p) * 0.6;
    n += surfaceValueNoise(p * 2.03 + float3(11.7, 3.1, 7.9)) * 0.28;
    n += surfaceValueNoise(p * 4.01 + float3(5.3, 17.2, 2.4)) * 0.12;
    return saturate((n - 0.2) / 0.6);
}

// 덮는 정도. up = 위를 보는 정도(-1~1), coverage = 0~1
float surfaceCoverMask(float up, float coverage)
{
    float soft = max(_SnowSoftness, 0.001);
    float edge = lerp(1.35 + soft, -1.35 - soft, saturate(coverage));
    return smoothstep(edge - soft, edge + soft, up);
}

// 위치와 월드 법선으로 눈 마스크. 정점 단계(부풀리기)와 픽셀 단계(색)가 같은 함수를 쓴다.
float SnowMask(float3 positionOS, float3 normalWS)
{
    float noise = surfaceNoise(positionOS * _NoiseScale);
    return surfaceCoverMask(normalWS.y + (noise - 0.5) * SURFACE_NOISE_AMOUNT, _Coverage);
}

// [직접 추가] 눈 덮인 정점을 법선 방향으로 밀어 눈 두께를 만든다.
float3 WinterToonVertex(float3 positionOS, float3 normalOS)
{
    float3 normalWS = TransformObjectToWorldNormal(normalOS);
    float mask = SnowMask(positionOS, normalWS);
    return positionOS + normalOS * _SnowHeight * mask;
}

// ---- 툰 (갤러리 램프 툰 조명) -------------------------------------------
float toonMax3(float3 c) { return max(c.r, max(c.g, c.b)); }

// 0~1 밝기를 _Bands 개의 띠로 끊는다
float toonBands(float level)
{
    float bands = max(floor(_Bands + 0.5), 2.0);
    float t = level * bands - 0.5;
    float cell = floor(t);
    float f = t - cell;
    float w = clamp(max(_Softness, fwidth(t)), 0.001, 0.5);   // 픽셀 하나보다 좁아지지 않게
    float stepped = cell + smoothstep(0.5 - w, 0.5 + w, f);
    return saturate(stepped / (bands - 1.0));
}

// ---- 합치기 -----------------------------------------------------------
struct WinterInput
{
    float2 uv;
    float3 positionOS;
    float3 normalWS;
    float3 viewWS;
    float3 lightDirWS;
    float3 lightColor;   // 빛 색 × 받는 그림자
};

float3 WinterToonColor(WinterInput i, float3 baseAlbedo)
{
    float3 n = i.normalWS;
    float ndl = dot(n, i.lightDirWS);

    // 1. 툰 계단: 빛의 양(그림자 포함)과 색조를 나눈 뒤, 밝기만 계단으로 끊는다
    float lightAmount = toonMax3(i.lightColor);
    float shadow = saturate(lightAmount);
    float3 lightHue = lerp(float3(1, 1, 1), i.lightColor / max(lightAmount, 0.0001), step(0.0001, lightAmount));
    float level = saturate((ndl - _ShadeShift) / (1.0 - _ShadeShift)) * shadow;
    float band = toonBands(level);

    // 2. 바탕과 눈 각각 그늘 색 ↔ 빛 색
    float3 baseCol = baseAlbedo * lerp(_ShadeColor.rgb, lightHue, band);
    float3 snowCol = _SnowColor.rgb * lerp(_SnowShadeColor.rgb, lightHue, band);

    // 눈 반짝임: 알갱이마다 법선을 틀어 몇 개만 빛을 반사 (갤러리 식). 빛을 받는 띠에서만.
    float3 h = normalize(i.lightDirWS + i.viewWS);
    float3 grain = floor(i.positionOS * SURFACE_GLINT_CELLS);
    float3 jitter = float3(surfaceHash(grain), surfaceHash(grain + float3(17, 5, 3)), surfaceHash(grain + float3(7, 29, 13))) - 0.5;
    float3 glintN = normalize(n + jitter * 0.9);
    float glintPick = step(0.8, surfaceHash(grain + float3(3, 11, 23)));
    float glint = glintPick * pow(saturate(dot(glintN, h)), 300.0) * step(0.0, ndl) * band;
    snowCol += lightHue * glint * _Glint;

    // 3. 눈 마스크로 섞기 (월드 법선 기준이라 물체를 돌려도 늘 위쪽에 쌓인다)
    float mask = SnowMask(i.positionOS, n);
    float3 color = lerp(baseCol, snowCol, mask);

    // 4. 툰 림: 윤곽값을 거듭제곱한 뒤 smoothstep 으로 끊어 딱 떨어지는 띠로 만든다.
    float edge = 1.0 - saturate(dot(n, i.viewWS));
    float rim = pow(max(edge, 0.0001), _RimPower);
    float hard = 0.5 * (1.0 - _RimHardness) + 0.001;
    rim = lerp(rim, smoothstep(0.5 - hard, 0.5 + hard, rim), step(0.001, _RimHardness));
    // 역광: 빛을 덜 받는 쪽 윤곽일수록 강하게 (_RimBacklight = 0 이면 사방에 같게)
    rim *= lerp(1.0, saturate(1.0 - band + 0.25), _RimBacklight);
    color += _RimColor.rgb * rim * _RimIntensity;

    return color;
}

#endif
