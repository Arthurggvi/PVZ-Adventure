shader_type canvas_item;
render_mode unshaded;

// 在 Compatibility 渲染器下对一次屏幕采样做湿镜头后处理。
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 viewport_size = vec2(1066.0, 600.0);
uniform float clock_seconds = 0.0;
uniform float soft_focus : hint_range(0.0, 1.0) = 0.36;
uniform float bloom_strength : hint_range(0.0, 1.0) = 0.62;
uniform float haze_strength : hint_range(0.0, 0.5) = 0.19;
uniform vec4 haze_color : source_color = vec4(0.67, 0.76, 0.85, 1.0);
uniform float droplet_strength : hint_range(0.0, 1.0) = 0.95;
uniform float refraction_strength : hint_range(0.0, 2.0) = 1.0;
uniform float wipe_radius = 58.0;
uniform float wipe_recovery_seconds = 2.6;
uniform float lightning = 0.0;
uniform vec4 wipe_points[24]; // xy: UV，z: 采样时刻，w: 有效标志。
uniform vec4 drops[20];       // xy: 水珠中心 UV，z: 半径像素，w: 滑动速度标量。

float rain_haze(vec2 uv) {
    float slow = 0.48 + 0.20 * sin(uv.x * 8.2 - uv.y * 4.0 + clock_seconds * 0.13);
    float detail = 0.12 * sin(uv.y * 21.0 + uv.x * 5.0 - clock_seconds * 0.09);
    return clamp(slow + detail, 0.1, 0.85);
}

float wipe_coverage(vec2 uv) {
    float cleared = 0.0;
    for (int i = 0; i < 24; i++) {
        vec4 mark = wipe_points[i];
        if (mark.w < 0.5) { continue; }
        float age = max(0.0, clock_seconds - mark.z);
        float fade = exp(-age / max(0.2, wipe_recovery_seconds));
        float distance_px = length((uv - mark.xy) * viewport_size);
        float brush = 1.0 - smoothstep(wipe_radius * 0.30, wipe_radius, distance_px);
        cleared = max(cleared, brush * fade);
    }
    return clamp(cleared, 0.0, 1.0);
}

// 真实状态由控制器维护，Shader 只将水珠转成折射场、边缘暗线、亮边和拖尾。
vec4 droplet_field(vec2 uv, out vec2 distortion) {
    vec4 fields = vec4(0.0); // x: 液滴内部，y: 边线，z: 高光，w: 纵向水痕。
    distortion = vec2(0.0);
    for (int i = 0; i < 20; i++) {
        vec4 drop = drops[i];
        if (drop.z <= 0.0) { continue; }
        vec2 p = (uv - drop.xy) * viewport_size;
        float elongation = 1.0 + drop.w * 1.25;
        vec2 ellipse = vec2(p.x, p.y / elongation);
        float radius = drop.z;
        float distance_px = length(ellipse);
        float body = 1.0 - smoothstep(radius * 0.64, radius * 1.08, distance_px);
        float edge = (smoothstep(radius * 0.66, radius * 0.91, distance_px)
                       - smoothstep(radius * 0.91, radius * 1.22, distance_px));
        float gleam = 1.0 - smoothstep(radius * 0.16, radius * 0.62,
            length(ellipse + vec2(radius * 0.32, radius * 0.36)));
        float upper_rim = edge * (1.0 - smoothstep(-radius * 0.6, radius * 0.35, ellipse.y)) * 0.7;
        float trail_width = 1.0 - smoothstep(radius * 0.10, radius * 0.28, abs(p.x));
        float trail_len = smoothstep(-radius * (6.0 + 4.0 * drop.w), -radius, p.y)
            * (1.0 - smoothstep(-radius * 0.95, -radius * 0.15, p.y));
        float trail = trail_width * trail_len * drop.w * 0.58;
        float variation = 0.54 + 0.42 * fract(sin(float(i) * 29.13 + 2.4) * 19234.17);
        fields = max(fields, vec4(body, edge, max(gleam * body, upper_rim), trail) * variation);
        if (body > 0.01) {
            distortion += clamp(ellipse / max(radius, 0.01), vec2(-1.0), vec2(1.0)) * body;
        }
    }
    return fields;
}

void fragment() {
    vec2 uv = SCREEN_UV;
    float clear_mask = wipe_coverage(uv);
    float wet = 1.0 - clear_mask;
    vec2 refract_normal;
    vec4 water = droplet_field(uv, refract_normal);
    float water_visibility = droplet_strength * wet;
    vec2 sample_uv = clamp(uv + refract_normal * 3.1 * refraction_strength *
        water_visibility / max(viewport_size, vec2(1.0)), vec2(0.001), vec2(0.999));

    vec3 sharp = textureLod(screen_texture, sample_uv, 0.0).rgb;
    vec3 smooth_mid = textureLod(screen_texture, sample_uv, 3.1).rgb;
    vec3 smooth_far = textureLod(screen_texture, sample_uv, 5.0).rgb;
    vec3 color = mix(sharp, smooth_mid, soft_focus * wet);
    color = mix(color, smooth_far, 0.11 * wet * soft_focus);

    // Bright-pass 防止把暗部一并发光；宽半径 mip 采样使高光向外溢出。
    float luminosity = dot(smooth_far, vec3(0.2126, 0.7152, 0.0722));
    vec3 bright_pass = max(smooth_far - vec3(0.27), vec3(0.0));
    color += bright_pass * bloom_strength * smoothstep(0.20, 0.72, luminosity) * (0.75 + wet * 0.25);
    float haze_amount = clamp(haze_strength * rain_haze(uv) * wet, 0.0, 0.36);
    color = mix(color, haze_color.rgb, haze_amount);

    // 边缘包围的暗-亮双层光，滑动水痕更薄，湿玻璃不产生白色实心圆。
    color -= vec3(0.049, 0.054, 0.058) * water.y * water_visibility;
    color += vec3(0.34, 0.39, 0.43) * water.z * water_visibility;
    color += vec3(0.068, 0.078, 0.089) * water.w * water_visibility;
    // 擦拭区域的水膜被推至边缘，出现短促湿亮边。
    float brush_rim = 4.0 * clear_mask * (1.0 - clear_mask);
    color += vec3(0.025, 0.04, 0.047) * brush_rim;

    // 可由关卡事件或演示控制器触发的低频闪电照明。
    color += vec3(0.43, 0.49, 0.68) * clamp(lightning, 0.0, 1.0) * (0.32 + 0.30 * luminosity);
    COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), 1.0);
}
