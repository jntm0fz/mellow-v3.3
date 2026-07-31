// 6 texture samples instead of 25, but it's 2 pass
// https://github.com/Experience-Monks/glsl-fast-gaussian-blur
vec3 blur(sampler2D image, vec2 texcoord, vec2 direction, float Scale, float Offset) {
    vec3 color = vec3(0.0);
    vec2 off1 = vec2(1.3333333333333333) * direction * resolutionInv;

    texcoord *= Scale;
    texcoord += Offset;

    float BoundLower = Offset;
    float BoundUpper = Offset + Scale;

    color += texture(image, texcoord).rgb * 0.29411764705882354;
    if (clamp(texcoord + off1 * 2, BoundLower, BoundUpper) == texcoord + off1 * 2)
        color += texture(image, texcoord + off1).rgb * 0.35294117647058826;
    if (clamp(texcoord - off1 * 2, BoundLower, BoundUpper) == texcoord - off1 * 2)
        color += texture(image, texcoord - off1).rgb * 0.35294117647058826;
    return color;
}

// 5 texture samples instead of 9
vec3 blur3x3(sampler2D image, vec2 texcoord) {
    vec2 d = 0.66 * resolutionInv;
    vec3 Color = texture(image, texcoord + vec2(-d.x, -d.y)).rgb;
    Color +=     texture(image, texcoord + vec2( d.x, -d.y)).rgb;
    Color +=     texture(image, texcoord + vec2(-d.x,  d.y)).rgb;
    Color +=     texture(image, texcoord + vec2( d.x,  d.y)).rgb;
    return Color * 0.25;
}

vec2 adjust_vertex_position(float TileSize, float MaxSize, float TileOffset, vec2 glPos) {
    vec2 TileSizeClamped = vec2(aspectRatio, 1) * vec2(TileSize);
    float Scale = max(1, min_component(TileSizeClamped) / min_component(resolution * MaxSize));
    glPos = (glPos * TileSizeClamped + TileOffset * vec2(aspectRatio, 1)) / Scale * resolutionInv;
    return glPos;
}