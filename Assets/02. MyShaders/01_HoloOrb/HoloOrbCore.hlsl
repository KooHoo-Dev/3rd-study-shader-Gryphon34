// =====================================================================
//  HoloOrbCore.hlsl — HoloOrb 효과 본체
//  shader-gallery 「인테리어 매핑」 + 「홀로그램」 응용
//
//  [인테리어 매핑 → 구 안의 방 하나]
//   갤러리 원본은 평평한 벽을 창 칸으로 나누고, 칸마다 창 뒤의 방 상자와 시선을 교차시킨다.
//   여기서는 오브 안에 "방 상자 하나"를 띄운다.
//   카메라에서 이 픽셀을 지나는 시선을 상자와 교차시키고, 시선이 상자를 "빠져나가는 점"(먼 쪽 벽)을
//   구하면 그곳이 우리가 보는 방 안쪽 벽이다. 구 표면은 그냥 유리창 역할만 한다.
//
//  [홀로그램]
//   프레넬 테두리 + 월드 높이로 흐르는 스캔라인 + floor 로 끊은 시간으로 띠를 미는 정점 글리치 + 깜빡임.
//   (상수와 해시, 글리치 함수는 갤러리 홀로그램 코드를 그대로 따른다)
// =====================================================================
#ifndef MYSHADERS_HOLOORB_CORE_INCLUDED
#define MYSHADERS_HOLOORB_CORE_INCLUDED

// ---- 홀로그램 상수 (갤러리 값) -----------------------------------------
#define HOLOGRAM_GLITCH_BANDS 4.0   // 오브젝트 높이 1 에 띠 4 개
#define HOLOGRAM_GLITCH_RATE 10.0   // 초당 띠를 다시 고르는 횟수
#define HOLOGRAM_BURST_RATE 2.0     // 0.5 초마다 이번 구간에 글리치를 낼지 정함
#define HOLOGRAM_GLITCH_MAX 0.18    // 띠를 미는 최대 거리 (오브젝트 공간)
#define HOLOGRAM_FLICKER_RATE 2.0   // 깜빡임은 2Hz 이하

// 0~1 격자 난수 (2D)
float hologramHash(float2 p)
{
    float3 q = frac(float3(p.x, p.y, p.x) * 0.1031);
    q = q + dot(q, q.yzx + 33.33);
    return frac((q.x + q.y) * q.z);
}

float hologramBand(float y, float slot)
{
    return floor(y * HOLOGRAM_GLITCH_BANDS + hologramHash(float2(slot, 5.3)));
}

// x: 이 높이의 띠가 지금 밀려 있으면 1 / yz: 오브젝트 공간 xz 로 미는 거리
float3 hologramGlitch(float y, float time)
{
    float strength = saturate(_GlitchStrength);
    float slot = floor(time * HOLOGRAM_GLITCH_RATE);          // 시간을 끊어야 "툭툭" 튄다
    float burstSlot = floor(time * HOLOGRAM_BURST_RATE);
    float burst = step(hologramHash(float2(burstSlot, 17.0)), strength * 0.8);
    float band = hologramBand(y, slot);
    float chosen = step(hologramHash(float2(band, slot)), 0.35) * burst;
    float angle = hologramHash(float2(band + 31.0, slot)) * 6.2831853;
    float reach = (0.4 + 0.6 * hologramHash(float2(band, slot + 71.0))) * strength * HOLOGRAM_GLITCH_MAX * chosen;
    return float3(chosen, cos(angle) * reach, sin(angle) * reach);
}

// 정점 글리치: 고른 띠의 정점만 옆으로 민다.
float3 HoloOrbVertex(float3 positionOS, float time)
{
    float3 g = hologramGlitch(positionOS.y, time);
    return positionOS + float3(g.y, 0.0, g.z);
}

// ---- 인테리어: 방 상자 ------------------------------------------------
// y 축 회전 (방이 오브 안에서 천천히 돈다)
float3 RotateY(float3 p, float a)
{
    float s = sin(a), c = cos(a);
    return float3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

// 절차적 방 그림. h 는 상자 좌표(-1~1), axis 는 닿은 면의 축(0=x,1=y,2=z), side 는 그 면의 부호.
float3 ProceduralRoom(float3 h, float axis, float side, out float3 emissive)
{
    emissive = 0;
    float3 albedo;

    if (axis == 1.0)
    {
        if (side < 0.0)
        {
            // 바닥: 체크 무늬 타일
            float2 c = (h.xz * 0.5 + 0.5) * _FloorTiles;
            float checker = frac((floor(c.x) + floor(c.y)) * 0.5) * 2.0;
            albedo = _FloorColor.rgb * lerp(0.55, 1.0, checker);
        }
        else
        {
            // 천장: 가운데 둥근 등
            albedo = _WallColor.rgb * 0.75;
            float lampDisc = 1.0 - smoothstep(0.14, 0.18, length(h.xz));
            emissive = _LampColor.rgb * lampDisc * 3.0;
        }
    }
    else
    {
        // 벽: 세로 판자 줄 + 아래쪽 걸레받이
        float across = (axis == 0.0) ? h.z : h.x;
        float panel = abs(frac((across * 0.5 + 0.5) * _WallPanels) - 0.5) * 2.0;   // 판 가운데 1, 이음새 0
        albedo = _WallColor.rgb * lerp(0.7, 1.0, smoothstep(0.0, 0.15, panel));
        albedo = lerp(albedo, _WallColor.rgb * 0.35, step(h.y, -0.82));

        // +Z 쪽 벽에는 바깥 빛이 들어오는 창문
        if (axis == 2.0 && side > 0.0)
        {
            float2 w = float2(across, h.y - 0.2);
            float inWindow = step(abs(w.x), 0.5) * step(abs(w.y), 0.4);
            float mullion = step(abs(w.x), 0.025) + step(abs(w.y), 0.025);            // 창살 십자
            float3 sky = lerp(_WindowColor.rgb, _WindowColor.rgb * 0.35, saturate(w.y / 0.4 * 0.5 + 0.5));
            emissive += sky * inWindow * (1.0 - saturate(mullion)) * 1.5;
            albedo = lerp(albedo, albedo * 0.2, inWindow);
        }
    }
    return albedo;
}

// 시선과 방 상자의 교차 → 방 안쪽 색. 상자를 비껴가면 hitRoom = 0.
float3 InteriorRoom(float3 positionOS, float3 cameraPosOS, float time, out float hitRoom)
{
    // 오브젝트 공간 시선. 방을 돌리는 대신 시선을 반대로 돌린다(같은 결과).
    float angle = -time * _RoomSpin;
    float3 ro = RotateY(cameraPosOS, angle);
    float3 rd = normalize(RotateY(positionOS - cameraPosOS, angle));

    // 슬랩(slab) 교차: 축마다 상자의 두 평면까지 거리를 구한다.
    // 0 으로 나누지 않게 아주 작은 값을 더한다.
    rd += step(abs(rd), 1e-5) * 1e-5;
    float3 inv = 1.0 / rd;
    float3 size = _RoomSize.xxx;
    float3 t1 = (-size - ro) * inv;
    float3 t2 = ( size - ro) * inv;
    float3 tEnter3 = min(t1, t2);
    float3 tExit3  = max(t1, t2);
    float tEnter = max(max(tEnter3.x, tEnter3.y), tEnter3.z);
    float tExit  = min(min(tExit3.x, tExit3.y), tExit3.z);   // 갤러리처럼 min 으로 "먼저 닿는 면"을 고른다

    hitRoom = step(tEnter, tExit) * step(0.0, tExit);

    // 나가는 면이 어느 축인지
    float axis = (tExit3.x <= tExit3.y && tExit3.x <= tExit3.z) ? 0.0 : ((tExit3.y <= tExit3.z) ? 1.0 : 2.0);
    float3 hitPos = ro + rd * tExit;
    float3 h = hitPos / size;                                   // 상자 좌표 -1~1
    float side = (axis == 0.0) ? sign(rd.x) : ((axis == 1.0) ? sign(rd.y) : sign(rd.z));

#if defined(_ROOMCUBE_ON)
    // 큐브맵 모드: 방 가운데에서 닿은 점 방향으로 큐브맵을 읽는다(박스 투영).
    float3 room = SAMPLE_TEXTURECUBE(_RoomCube, sampler_RoomCube, h).rgb * _CubeExposure;
#else
    float3 emissive;
    float3 albedo = ProceduralRoom(h, axis, side, emissive);

    // 천장 가운데 등에 가까울수록 밝다 (갤러리 인테리어의 등빛 식: 1 / (1 + k·거리²))
    float3 toLamp = h - float3(0.0, 0.95, 0.0);
    float glow = 1.0 / (1.0 + _LampFalloff * dot(toLamp, toLamp));
    float3 light = _RoomAmbient + _LampColor.rgb * glow * _LampIntensity;
    float3 room = albedo * light + emissive;
#endif
    return room;
}

// ---- 합치기 -----------------------------------------------------------
struct OrbInput
{
    float3 positionOS;
    float3 positionWS;
    float3 normalWS;
    float3 viewWS;
    float3 cameraPosOS;
    float  time;
};

float3 HoloOrbColor(OrbInput i)
{
    // 1. 방 안쪽
    float hitRoom;
    float3 room = InteriorRoom(i.positionOS, i.cameraPosOS, i.time, hitRoom);
    room = lerp(_VoidColor.rgb, room, hitRoom);                 // 방 바깥(빈 공간)은 안개색

    // 2. 홀로그램 색 입히기: 방의 밝기만 남겨 홀로그램 색으로 칠한다.
    float lum = dot(room, float3(0.299, 0.587, 0.114));
    float3 interior = lerp(room, lum * _HoloColor.rgb * 1.6, _HoloTint);

    // 3. 프레넬 테두리
    float rim = pow(1.0 - saturate(dot(i.normalWS, i.viewWS)), _RimPower);

    // 4. 스캔라인 (월드 높이 기준이라 오브가 돌아도 줄은 수평)
    float cell = frac((i.positionWS.y - i.time * _ScanSpeed) / _LineSpacing);
    float lines = 1.0 - smoothstep(0.08, 0.3, abs(cell - 0.5));
    interior *= 1.0 - _ScanStrength * 0.5 * (1.0 - lines);     // 줄 사이를 어둡게

    // 5. 글리치로 밀린 띠는 살짝 밝게
    float glitched = hologramGlitch(i.positionOS.y, i.time).x;

    // 6. 깜빡임
    float flickSlot = floor(i.time * HOLOGRAM_FLICKER_RATE);
    float dip = step(0.5, hologramHash(float2(flickSlot, 41.0))) * (0.5 + 0.5 * hologramHash(float2(flickSlot, 43.0)));
    float flicker = 1.0 - _Flicker * 0.7 * dip;

    float3 glowAdd = _HoloColor.rgb * (rim * _RimStrength + lines * _ScanStrength * 0.25 + glitched * 0.3);
    return (interior + glowAdd) * flicker;
}

#endif
