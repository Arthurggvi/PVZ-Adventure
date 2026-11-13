shader_type canvas_item;
render_mode unshaded;

// 单次全分辨率合成。雨、雾、镜头水珠使用同一组离屏发光数据。
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D light_field : source_color, filter_linear;
uniform sampler2D bloom_tight : source_color, filter_linear;
uniform sampler2D bloom_wide : source_color, filter_linear;
uniform bool has_light_field = false;
uniform float bloom_tight_gain = 0.44;
uniform float bloom_wide_gain = 0.78;
uniform float air_scatter_gain = 0.52;
uniform float droplet_light_gain = 0.72;
uniform vec2 viewport_size = vec2(1066.0, 600.0);
uniform float clock_seconds = 0.0;
uniform float soft_focus : hint_range(0.0, 1.0) = 0.47;
uniform float bloom_strength : hint_range(0.0, 1.0) = 0.70;
uniform float haze_strength : hint_range(0.0, 0.5) = 0.23;
uniform vec4 haze_color : source_color = vec4(0.67, 0.76, 0.85, 1.0);
uniform float droplet_strength : hint_range(0.0, 1.0) = 0.89;
uniform float refraction_strength : hint_range(0.0, 2.0) = 1.0;
uniform float wipe_recovery_seconds = 2.6;
uniform float lightning = 0.0;
uniform sampler2D wipe_mask : repeat_disable, filter_linear; // R 为水膜擦除的等效时间，不作颜色解码。
uniform vec4 drops[20]; // xy: screen UV; z: radius pixel; w: fall factor.

float rain_haze(vec2 uv) {
    float a = 0.48 + 0.20 * sin(uv.x * 8.2 - uv.y * 4.0 + clock_seconds * 0.13);
    float b = 0.12 * sin(uv.y * 21.0 + uv.x * 5.0 - clock_seconds * 0.09);
    return clamp(a + b, 0.1, 0.85);
}

float wipe_coverage(vec2 uv) {
    float stamp = texture(wipe_mask, uv).r;
    return exp(min(0.0, (stamp - clock_seconds) / max(0.2, wipe_recovery_seconds)));
}

// 各水珠沿用独立模拟器的运动学状态，此处只重建局部法线与高光。
vec4 droplet_field(vec2 uv, out vec2 distortion) {
    vec4 result = vec4(0.0); // body, rim, glint, trail
    distortion = vec2(0.0);
    for (int i = 0; i < 20; i++) {
        vec4 drop = drops[i];
        if (drop.z <= 0.0) { continue; }
        vec2 delta = (uv - drop.xy) * viewport_size;
        vec2 p = vec2(delta.x, delta.y / (1.0 + drop.w * 1.25));
        float r = drop.z;
        float dist = length(p);
        float body = 1.0 - smoothstep(r * 0.64, r * 1.08, dist);
        float edge = smoothstep(r * 0.66, r * 0.91, dist) -
                     smoothstep(r * 0.91, r * 1.22, dist);
        float glint = 1.0 - smoothstep(r * 0.16, r * 0.62,
            length(p + vec2(r * 0.32, r * 0.36)));
        float rim = edge * (1.0 - smoothstep(-r * 0.6, r * 0.35, p.y)) * 0.7;
        float trail_x = 1.0 - smoothstep(r * 0.10, r * 0.28, abs(delta.x));
        float trail_y = smoothstep(-r * (6.0 + 4.0 * drop.w), -r, delta.y) *
            (1.0 - smoothstep(-r * 0.95, -r * 0.15, delta.y));
        float variation = 0.54 + 0.42 * fract(sin(float(i) * 29.13 + 2.4) * 19234.17);
        result = max(result, vec4(body, edge, max(glint * body, rim),
            trail_x * trail_y * drop.w * 0.58) * variation);
        distortion += clamp(p / max(r, 0.01), vec2(-1.0), vec2(1.0)) * body;
    }
    return result;
}

void fragment() {
    vec2 uv = SCREEN_UV;
    float wiped = wipe_coverage(uv);
    float water = 1.0 - wiped;
    vec2 normal;
    vec4 drop = droplet_field(uv, normal);
    float water_alpha = droplet_strength * water;
    vec2 sample_uv = clamp(uv + normal * 3.1 * refraction_strength *
        water_alpha / max(viewport_size, vec2(1.0)), vec2(0.001), vec2(0.999));

    vec3 original = textureLod(screen_texture, sample_uv, 0.0).rgb;
    vec3 soft = textureLod(screen_texture, sample_uv, 4.2).rgb;
    vec3 soft_wide = textureLod(screen_texture, sample_uv, 5.5).rgb;
    vec3 illumination = has_light_field ? texture(light_field, sample_uv).rgb : vec3(0.0);
    float illumination_luma = dot(illumination, vec3(0.2126, 0.7152, 0.0722));
    float haze_noise = rain_haze(uv);
    float local_softness = clamp(soft_focus * (0.55 + 0.44 * haze_noise + 0.22 *
        illumination_luma) * water, 0.0, 0.82);
    vec3 color = mix(original, soft, local_softness);
    color = mix(color, soft_wide, local_softness * 0.15);

    // 镜头水膜可擦除；真实空气中的雨雾不会被鼠标擦除。
    float air_haze = clamp(haze_strength * haze_noise * 0.45, 0.0, 0.19);
    float lens_haze = clamp(haze_strength * haze_noise * 0.90 * water, 0.0, 0.30);
    color = mix(color, haze_color.rgb, air_haze + lens_haze);

    if (has_light_field) {
        // 多尺度 bloom 来自独立光源缓冲：先标记发光信息再离屏模糊。
        vec3 tight = texture(bloom_tight, uv).rgb;
        vec3 wide = texture(bloom_wide, uv).rgb;
        vec3 glow = tight * bloom_tight_gain * 0.72 + wide * bloom_wide_gain * 1.05;
        float image_brightness = dot(original, vec3(0.2126, 0.7152, 0.0722));
        float high_light_protect = 1.0 - 0.40 * smoothstep(0.72, 0.98, image_brightness);
        color += glow * bloom_strength * high_light_protect * (0.86 + 0.14 * water);
        // 带运动密度场的二维屏幕空间空气散射，不随擦拭消失。
        color += (illumination * 0.65 + wide * 0.35) * (0.17 + 0.60 * haze_noise) *
            air_scatter_gain * haze_strength * 1.10;
    } else {
        // 其它未配置地图光源的雨关兼容老版本基于画面亮度的轻微泛光。
        float luminosity = dot(soft_wide, vec3(0.2126, 0.7152, 0.0722));
        color += max(soft_wide - vec3(0.27), vec3(0.0)) *
            smoothstep(0.36, 0.82, luminosity) * bloom_strength;
    }

    // 受光水珠局部高光采样统一光场，保留原版折射与遮罩。
    color -= vec3(0.049, 0.054, 0.058) * drop.y * water_alpha;
    color += vec3(0.24, 0.28, 0.32) * drop.z * water_alpha;
    color += vec3(0.068, 0.078, 0.089) * drop.w * water_alpha;
    color += illumination * droplet_light_gain * (drop.z * 0.35 + drop.w * 0.08) * water_alpha;

    color += vec3(0.43, 0.49, 0.68) * clamp(lightning, 0.0, 1.0) *
        (0.32 + 0.25 * illumination_luma);
    // 标准动态范围下软压缩极端高光，而不是简单硬裁纯白。
    vec3 excess = max(color - vec3(0.87), vec3(0.0));
    color = min(color, vec3(0.87)) + excess / (vec3(1.0) + excess * 2.1);
    COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), 1.0);
}
