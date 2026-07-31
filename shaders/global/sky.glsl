float fogify(float x, float w) {
    return w / (x * x + w);
}

vec3 round_sun(float Dist) {
    Dist = Dist * 0.5 + 0.5;
    const vec3 SUN_COLOR = vec3(5, 3.5, 0.8);
    const vec3 MOON_COLOR = vec3(1, 1.5, 2.5);
    float What = sunriseStrength + sunsetStrength;
    vec3 Color = SUN_COLOR * (1 - smoothstep(0., 0.0015, 1 - Dist)) * (dayStrength + What);
    Color += MOON_COLOR * (smoothstep(0.9995, 1., 1 - Dist)) * (nightStrength + What);
    Color *= 1 - rainStrength;
    return Color;
}

vec3 get_sun_glare(float Dist) {
    const vec3 SUN_GLARE = to_linear(vec3(f_SUN_GLARE_R, f_SUN_GLARE_G, f_SUN_GLARE_B));

    float DarkenFactor = 1 - rainStrength * RAIN_SKY_DARKENING;
    #ifdef IS_IRIS
        DarkenFactor *= 1 - thunderStrength * 0.75;
    #endif

    vec3 SunGlare = SUN_GLARE * DarkenFactor;
    float Visibility = sunsetStrength + sunriseStrength;
    Visibility = pow2(Visibility);

    return SunGlare * pow2(Dist * 0.5 + 0.5) * Visibility;
}

vec3 get_sky(vec3 ViewPosN, vec3 SunGlare) {
    float upDot = dot(ViewPosN, gbufferModelView[1].xyz) + 0.1; //not much, what's up with you?

    vec3 MixedColor = mix(SKY_TOP, SKY_GROUND + SunGlare, fogify(max(upDot, 0.0), 0.03));
    
    return MixedColor;
}

float get_stars(vec3 PlayerPos) {
    vec3 StarCoord = PlayerPos / (PlayerPos.y + length(PlayerPos.xz));
    StarCoord.x += frameTimeCounter * 0.001;
    const float ACTUAL_STAR_SIZE = STAR_SIZE * 512;
    StarCoord = floor(StarCoord * ACTUAL_STAR_SIZE) / ACTUAL_STAR_SIZE;

    float Visibility = smoothstep(0.0, 0.1, StarCoord.y); // Smoothly fade out stars near the bottom of the sky
    #ifdef DIMENSION_OVERWORLD
    Visibility *= nightStrength;
    #endif
    return max(0, random(StarCoord.xz) - 0.996) * 50 * Visibility * STAR_STRENGTH;
}

vec3 get_aurora(vec3 PlayerPosN, float Dither) {
    float AuroraStrength = AURORA_STRENGTH * nightStrength;
    #ifndef AURORA_EVERYWHERE
        if(precipitationSmooth <= 1.01) return vec3(0);
        AuroraStrength *= precipitationSmooth - 1;
    #endif
    
    const vec3 COLOR_TOP = pow(vec3(28, 255, 218) / 255.0, vec3(2.2));
    const vec3 COLOR_BOTTOM = pow(vec3(122, 255, 28) / 255.0, vec3(2.2));

    // Calculate intersection with aurora plane
    const float PLANE_TOP = 10.0 + AURORA_HEIGHT;
    const float PLANE_BOTTOM = 10.0;

    vec3 StartPos = PLANE_BOTTOM / PlayerPosN.y * PlayerPosN; 
    vec3 EndPos = PLANE_TOP / PlayerPosN.y * PlayerPosN;

    const int SAMPLE_COUNT = 2;

    vec3 Step = (EndPos - StartPos) / SAMPLE_COUNT;
    vec3 Pos = Step * Dither + StartPos;

    vec2 Wind = frameTimeCounter * vec2(0.25, 0.33);

    vec3 AuroraColor = vec3(0);
    for(int i = 1; i <= SAMPLE_COUNT; i++) {
        float Noise = texture(noisetex, (Pos.xz - Wind) / vec2(100, 200)).r;

        Noise = pow2(pow4(Noise));
        Noise *= smoothstep(0.0, 0.2, PlayerPosN.y);
        AuroraColor += Noise * mix(COLOR_BOTTOM, COLOR_TOP, smoothstep(0, 1, Dither));

        Pos += Step;
    }

    return AuroraColor * AuroraStrength / SAMPLE_COUNT;
}

vec3 get_end_sky(vec3 ViewPosN, vec3 PlayerPosN) {
    const vec3 SkyT = to_linear(vec3(f_END_SKY_T_R, f_END_SKY_T_G, f_END_SKY_T_B));
    const vec3 SkyG1 = to_linear(vec3(f_END_AURORA1_R, f_END_AURORA1_G, f_END_AURORA1_B));
    const vec3 SkyG2 = to_linear(vec3(f_END_AURORA2_R, f_END_AURORA2_G, f_END_AURORA2_B));

    float upDot = dot(ViewPosN, gbufferModelView[1].xyz); //not much, what's up with you?

    vec2 RotPos1 = rotate(PlayerPosN.xz, frameTimeCounter * 0.02);
    vec2 RotPos2 = rotate(PlayerPosN.xz, -frameTimeCounter * 0.007);

    float Noise1 = fbm_fast(RotPos1 * 160, 2);
    float Noise2 = fbm_fast(RotPos2 * 280, 2);
    float VerticalFactor = 1 - abs(upDot);
    vec3 SkyG = (SkyG1 * Noise1 + SkyG2 * Noise2) * VerticalFactor; // End lights

    #if MC_VERSION >= 12109
        float DistFromFlash = distance(PlayerPosN.xz, normalize(view_player(endFlashPosition, false)).xz);
        float BoostFromFlash = (1 + max(0, 5 - DistFromFlash * 8) * endFlashIntensity); 
        SkyG *= BoostFromFlash;
    #endif

    vec3 Final = SkyT + SkyG * (fogify(upDot + 0.2, 0.05)); 

    Final *= 1 - fogify(max(upDot + 0.2, 0), 0.02); // Void at the bottom

    return Final;
}

vec3 get_sky_main(vec3 ViewPosN, vec3 PlayerPosN, vec3 SunGlare) {
    #ifdef DIMENSION_OVERWORLD
        vec3 SkyColor = get_sky(ViewPosN, SunGlare);
    #elif defined DIMENSION_END
        vec3 SkyColor = get_end_sky(ViewPosN, PlayerPosN);
    #elif defined DIMENSION_NETHER
        vec3 fogColorL = to_linear(fogColor.rgb);
        fogColorL += 1e-6; // Need to prevent nans when fog is vec3(0)
        vec3 SkyColor = mix(fogColorL, normalize(fogColorL), 0.4) / 3;
    #elif defined DIMENSION_GENERIC
        float upDot = dot(ViewPosN, gbufferModelView[1].xyz);
        vec3 SkyColor = to_linear(fogColor.rgb) * mix(1, fogify(max(upDot + 0.2, 0), 0.02), 0.7);
    #endif

    return SkyColor;
}

vec3 get_rainbow(vec3 PlayerPos, vec3 PlayerPosN) {
    #if RAINBOWS == 1
        if(rainbowStrength < 0.0001) return vec3(0);
    #endif
    const float SIZE = 10.0;
    bool IsPastNoon = sunriseStrength <= sunsetStrength && sunAngleAtHome > 0.25;
    float P = 100 * (float(IsPastNoon) * 2 - 1) / PlayerPosN.x;
    if(P < 0) return vec3(0);

    vec3 RainbowPlane = P * PlayerPosN;
    
    float LHeight = sin(sunAngleAtHome * PI * 2);
    float Hue = distance(vec3((float(IsPastNoon) * 2 - 1) * 100, -100 * LHeight, 0), RainbowPlane) / SIZE;
    if(Hue < SIZE || Hue > SIZE + 1) return vec3(0);

    float Len = length(PlayerPos);
    float Brightness = pow4(1 - clamp((P - Len) / 100, 0, 1));

    float LHeight45 = max(0, sin(fract(sunAngle * 4) / 4 * PI * 8 - PI / 2)); // Peaks at 45deg
    Brightness *= LHeight45;

    float EdgeFade = smoothstep(0.0, 0.5, 1-abs(Hue - SIZE - 0.5)*2);
    Brightness *= EdgeFade;

    #if RAINBOWS == 1
        Brightness *= rainbowStrength;
    #endif

    vec3 Col = hsv_to_rgb(vec3(1 - (Hue + 0.15), 1, 0.15 * Brightness));

    return Col * SUN_DIRECT * RAINBOW_STRENGTH * (1 - nightStrength);
}
