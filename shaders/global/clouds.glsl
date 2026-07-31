vec3 get_clouds_flat(vec3 ViewPosN, vec3 PlayerPos, vec3 PlayerPosN, vec3 SunGlare, vec3 SkyColor) {
    vec2 CloudPos = PlayerPos.xz / (PlayerPos.y + length(PlayerPos.xz) / 6);

    const float ACTUAL_CLOUD_SPEED = CLOUD_SPEED / 100.;
    float Animation = float(frameTimeCounter) * ACTUAL_CLOUD_SPEED;
    CloudPos += cameraPosition.xz / 512;
    CloudPos = (CloudPos + Animation) * 32;

    float Noise = noise(CloudPos);
    float CloudAmount = CLOUD_AMOUNT / 100.0 + (rainStrength + thunderStrength) / 5;
    Noise *= smoothstep(0.0, 0.4 - CLOUD_OPACITY, Noise - 0.6 + CloudAmount);
    Noise *= smoothstep(0.0, 0.2, PlayerPosN.y);

    // Ultimate RTX raytraced ptgi 2000 cloud lighting
    const float DENSITY = 1.5;
    float Transmittance = exp(-Noise * DENSITY);
    float Absorbtion = noise(CloudPos + view_player(sunOrMoonPosN, false).xz * 8);
    Absorbtion = Absorbtion * 1.5;

    float LHeight = sin(sunAngleAtHome * PI * 2);
    vec3 CloudColorRaw = (SKY_GROUND * 2 + SunGlare);
    vec3 CloudColor = CloudColorRaw * 0.25 / PI;

    float VdotL = dot(ViewPosN, sunOrMoonPosN);
    float MiePhase = max(xlf_phase(VdotL, 0.7) * 1.5, 1 / PI);
    CloudColor += SUN_DIRECT * MiePhase * exp(-Absorbtion * DENSITY);

    #ifdef IS_IRIS
        if(lightningBoltPosition.w > 0) {  
            CloudColor += vec3(1) * exp(-DENSITY * distance(lightningBoltPosition.xz / far, PlayerPosN.xz) * 4);
        }
    #endif

    return SkyColor * Transmittance + CloudColor * Noise * DENSITY;
}

vec3 get_clouds_volumetric(vec3 ViewPosN, vec3 PlayerPos, vec3 PlayerPosN, vec3 SunGlare, vec3 SkyColor, float Dither) {
    const float PLANE_TOP = 1500.0;
    const float PLANE_BOTTOM = 1000.0;

    const float CLOUD_EXTINCTION = 0.5;
    const float CLOUD_SCATTERING = CLOUD_EXTINCTION;

    const int SAMPLE_COUNT = 8;

    vec3 StartPos = PLANE_BOTTOM / PlayerPosN.y * PlayerPosN; 
    vec3 EndPos = PLANE_TOP / PlayerPosN.y * PlayerPosN;

    vec3 Step = (EndPos - StartPos) / SAMPLE_COUNT;
    float StepSize = length(Step);
    vec3 Pos = Step * Dither + StartPos + vec3(cameraPosition.x, 0, cameraPosition.z);

    vec3 Wind = frameTimeCounter * vec3(12, 0, 16) * CLOUD_SPEED;
    float CloudAmount = (CLOUD_AMOUNT - 12) / 10.0 + (rainStrength + thunderStrength * 0.5);
    
    float VdotL = dot(ViewPosN, sunOrMoonPosN);
    float Phase = max(xlf_phase(VdotL, 0.7) * 1.5, 1 / PI);

    vec3 TotalScattering = vec3(0); float TotalTransmittance = 1;
    for(int i = 1; i <= SAMPLE_COUNT; i++) {
        float Base = texture(noisetex, (Pos.xz - Wind.xz) * 0.00007).r;

        float Alt = rescale(PLANE_BOTTOM, PLANE_TOP, Pos.y);
        float HeightDensity = linstep(0.0, 0.75, 1 - Alt) * linstep(0.0, 0.2, Alt);
        Base = pow(Base, 13 - CloudAmount * 5 + (1-HeightDensity) * 5);

        if(Base < 1e-4) {
            Pos += Step;
            continue;
        }

        float DetailTop = texture(colortex6, (Pos) / vec3(64) * 0.05).r;
        float DetailBottom = texture(colortex6, (Pos) / vec3(64) * 0.0125).r;
        Base = max(0, Base - DetailBottom * DetailTop * 0.1);

        float fms = CLOUD_SCATTERING * (1 - exp(-2.5 * Base * CLOUD_EXTINCTION)) / CLOUD_EXTINCTION;
        float MS = ISOTROPIC_PHASE * fms / (1 - fms);

        vec3 Scattering = (SKY_GROUND * 2 + SunGlare) * ISOTROPIC_PHASE;

        float LightFactor = linstep(PLANE_BOTTOM, PLANE_TOP, Pos.y) * 0.7 + 0.3;
        Scattering += SUN_DIRECT * (Phase + MS) * 1.5 * LightFactor;

        float Transmittance = exp(-Base * StepSize * CLOUD_EXTINCTION);
        Scattering *= CLOUD_SCATTERING * TotalTransmittance * (1 - Transmittance) / CLOUD_EXTINCTION;

        TotalScattering += Scattering;
        TotalTransmittance *= Transmittance;

        if(TotalTransmittance < 0.01) break;

        Pos += Step;
    }

    vec3 FinalColor = SkyColor * TotalTransmittance + TotalScattering;
    FinalColor = mix(SkyColor, FinalColor, linstep(0, 0.3, PlayerPosN.y) * (CLOUD_OPACITY + 0.5));

    return FinalColor;
}

vec3 get_clouds_blocky_volumetric(vec3 ViewPosN, vec3 PlayerPos, vec3 PlayerPosN, vec3 SunGlare, vec3 SkyColor, float Dither) {
    const float PLANE_TOP = 1100.0;
    const float PLANE_BOTTOM = 1000.0;

    const float CLOUD_EXTINCTION = 0.5;
    const float CLOUD_SCATTERING = CLOUD_EXTINCTION;

    const int SAMPLE_COUNT = 16;

    vec3 StartPos = PLANE_BOTTOM / PlayerPosN.y * PlayerPosN; 
    vec3 EndPos = PLANE_TOP / PlayerPosN.y * PlayerPosN; 
    vec3 Pos = StartPos + vec3(cameraPosition.x, 0, cameraPosition.z);

    vec3 Wind = frameTimeCounter * vec3(4, 0, 0) * CLOUD_SPEED;
    Pos += Wind;

    float Density = texture(colortex3, Pos.xz * 0.000025).a; // Sample right at the beginning
    vec2 TextureSize = textureSize(colortex3, 0);
    if(Density < 1e-2) { 
        // Travel to the edge of the next texel
        for(int i = 1; i < SAMPLE_COUNT; i++) {
            vec2 TexelPos = fract(Pos.xz * 0.000025 * TextureSize);
            vec2 DistToNext = ((step(0, PlayerPosN.xz)) - TexelPos) / PlayerPosN.xz / TextureSize;
            Pos += (PlayerPosN * min(DistToNext.x, DistToNext.y)) / 0.000025;
            Pos += 0.002 * sign(vec3(PlayerPosN.x, 0, PlayerPosN.z)); // Bias to make sure we sample the correct texel
            
            if(Pos.y > PLANE_TOP) { // Break if we go too high
                break;
            }
            Density = texture(colortex3, Pos.xz * 0.000025).a;
            
            if(Density > 1e-2) {
                break;
            }
        }
    }
    if(Density < 1e-2) return SkyColor;

    // Lighting

    // Same DDA, for the sun ray
    vec3 SunOffset = view_player(sunOrMoonPosN, false);

    vec3 SunSamplePos = Pos;
    float SunT = 1;
    for(int i = 1; i <= 6; i++) {
        vec3 TexelPos;
        TexelPos.xz = fract(SunSamplePos.xz * 0.000025 * TextureSize);
        TexelPos.y = rescale(PLANE_BOTTOM, PLANE_TOP, SunSamplePos.y);
        vec3 DistToNext = ((step(0, SunOffset)) - TexelPos) / SunOffset / vec3(TextureSize.x, 1. / (PLANE_TOP - PLANE_BOTTOM), TextureSize.y);
        DistToNext.xz /= 0.000025;
        float MinDist = min_component(DistToNext);
        SunSamplePos += SunOffset * MinDist;
        SunSamplePos += 0.001 * sign(SunOffset); // Bias to make sure we sample the correct texel

        float SunSample = texture(colortex3, SunSamplePos.xz * 0.000025).a;
        SunT *= exp(-(MinDist * 0.03) * CLOUD_EXTINCTION); 
        if(SunT < 1e-4 || SunSamplePos.y > PLANE_TOP || SunSamplePos.y < PLANE_BOTTOM || SunSample < 1e-2) break;
    }

    float LightFactor = linstep(PLANE_BOTTOM, PLANE_TOP, Pos.y) * 0.7 + 0.3;
    vec3 Scattering = (SKY_GROUND + SunGlare) * LightFactor;

    float VdotL = dot(ViewPosN, sunOrMoonPosN);
    float Phase = max(xlf_phase(VdotL, 0.7) * 1.5, 1 / PI);

    Scattering += SUN_DIRECT * Phase * SunT;

    float Transmittance = exp(-Density * 2 * CLOUD_EXTINCTION);
    Scattering *= CLOUD_SCATTERING * (1 - Transmittance) / CLOUD_EXTINCTION;


    vec3 FinalColor = SkyColor * Transmittance + Scattering;
    FinalColor = mix(SkyColor, FinalColor, linstep(0, 0.3, PlayerPosN.y) * (CLOUD_OPACITY + 0.5));

    return FinalColor;
}


vec3 get_clouds(vec3 ViewPosN, vec3 PlayerPos, vec3 PlayerPosN, vec3 SunGlare, vec3 SkyColor, float Dither) {
    #if CLOUD_STYLE == 0
        return SkyColor;
    #elif CLOUD_STYLE == 1
        return get_clouds_flat(ViewPosN, PlayerPos, PlayerPosN, SunGlare, SkyColor);
    #elif CLOUD_STYLE == 2
        return get_clouds_volumetric(ViewPosN, PlayerPos, PlayerPosN, SunGlare, SkyColor, Dither);
    #elif CLOUD_STYLE == 3
        return get_clouds_blocky_volumetric(ViewPosN, PlayerPos, PlayerPosN, SunGlare, SkyColor, Dither);
    #endif
}
