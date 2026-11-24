shader_type canvas_item;
render_mode unshaded, blend_mix;

// 复用主菜单显式周期与静止模式；地图水面新增流场输运和伪物理光学。
#include "res://shaders/ui/main_menu/water_surface.gdshaderinc"
#include "res://shaders/adventure/wonderland/water_spectral.gdshaderinc"

// 区域R为运动权重；海洋G为完整湿域体色覆盖、B为岸距/64。流场RG流向、B速度、A位移保护。
uniform sampler2D region_mask : filter_linear, repeat_disable;
uniform sampler2D flow_field : filter_linear, repeat_disable;
// 稳定世界尺寸、高清图块采样原点、原图密度与半开核心范围。
uniform vec2 map_world_size = vec2(1774.0, 887.0);
uniform vec2 tile_pixel_origin = vec2(0.0);
uniform float pixels_per_world = 4.6178128523;
uniform vec4 core_pixel_rect = vec4(0.0, 0.0, 2048.0, 2048.0);
// 输运、折射和RGB色散合计限幅；24像素留边覆盖4世界单位。
uniform float amplitude_world : hint_range(0.0, 4.0) = 3.2;
// 波长仅保留给径向模式；默认水面形态由预计算状态决定。
uniform vec2 wavelength_world = vec2(20.0, 11.0);
// 反射与聚光的共同显示强度。
uniform float shimmer_strength : hint_range(0.0, 0.08) = 0.045;
// 兼容原字段名，现控制RGB折射率差异，已取消彩色宽带。
uniform float aurora_strength : hint_range(0.0, 0.6) = 0.38;
// 体色介质空间尺度，零体色模式沿用于薄层厚度；旧扭转参数仅兼容，物理波面由原图集决定。
uniform vec2 aurora_scale_world = vec2(90.0, 38.0);
uniform float swirl_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec2 swirl_center_world = vec2(170.0, 760.0);
// 区域覆盖权重，关闭时由静态地形接管。
uniform float effect_strength : hint_range(0.0, 1.0) = 1.0;

// 离线浅水状态：RG为坡度，B为波高，A为同场Snell聚光强度。
uniform sampler2D surface_state : filter_linear, repeat_disable;
// 每帧有效网格、图集布局与帧间采样隔离边。
uniform vec2 state_frame_size = vec2(384.0, 360.0);
uniform vec2 state_atlas_grid = vec2(8.0);
uniform float state_frame_count = 64.0;
uniform float state_padding = 2.0;
// 物理域的世界位置以及编码量程。
uniform vec2 state_origin_world = vec2(0.0, 168.0);
uniform vec2 state_extent_world = vec2(768.0, 720.0);
uniform float state_slope_range = 0.45;
uniform float state_height_range = 1.5;

// 图集各帧独立空间采样，帧间不依赖纹理硬件跨格过滤。
vec4 state_frame(vec2 point, float frame) {
    vec2 stride = state_frame_size + vec2(state_padding * 2.0);
    vec2 cell = vec2(mod(frame, state_atlas_grid.x), floor(frame / state_atlas_grid.x));
    vec2 pixel = clamp((point - state_origin_world) / state_extent_world * state_frame_size - vec2(0.5), vec2(0.0), state_frame_size - vec2(1.0));
    return texture(surface_state, (cell * stride + vec2(state_padding + 0.5) + pixel) / (stride * state_atlas_grid));
}

// 当前相位只读取同一浅水模拟的相邻状态；先插值坡度再重建法线。
vec4 wave_surface(vec2 point) {
    float position = fract(water_angle / 6.28318530718) * state_frame_count;
    float first = floor(position);
    vec4 state = mix(state_frame(point, first), state_frame(point, mod(first + 1.0, state_frame_count)), fract(position));
    return vec4((state.rg * 2.0 - 1.0) * state_slope_range, (state.b * 2.0 - 1.0) * state_height_range, 0.4 + state.a * 1.8);
}

// 每个最终采样独立校验总位移、图块留边和水岸，包括色散红蓝通道。
vec3 safe_water_sample(sampler2D terrain, vec2 source_pixel, vec2 offset_world, vec2 texel) {
    // 合成后的矢量限幅，防止对角运动超过预算。
    vec2 bounded_offset = offset_world * min(1.0, clamp(amplitude_world, 0.0, 4.0) / max(length(offset_world), 0.0001));
    vec2 full_size = map_world_size * pixels_per_world;
    vec2 sample_pixel = clamp(source_pixel + bounded_offset * pixels_per_world, vec2(0.5), full_size - vec2(0.5));
    vec2 map_uv = sample_pixel / full_size;
    vec2 local_uv = (sample_pixel - tile_pixel_origin) * texel;
    // 不安全时回退原位置，禁止把岸石颜色拖入水里。
    if (texture(region_mask, map_uv).r <= 0.0 || texture(flow_field, map_uv).a <= 0.0 || any(lessThan(local_uv, texel * 0.5)) || any(greaterThan(local_uv, vec2(1.0) - texel * 0.5))) {
        local_uv = (source_pixel - tile_pixel_origin) * texel;
    }
    return texture(terrain, local_uv).rgb;
}

// Snell折射相对平静水面的落点偏移，光学深度仅是2D原画的视觉近似。
vec2 refracted_offset(vec3 normal, float index) {
    vec3 incident = normalize(vec3(0.0, 0.65, -0.76));
    vec3 ray = refract(incident, normal, 1.0 / index);
    vec3 flat_ray = refract(incident, vec3(0.0, 0.0, 1.0), 1.0 / index);
    return (ray.xy / max(-ray.z, 0.25) - flat_ray.xy / max(-flat_ray.z, 0.25)) * 12.0;
}

// RGB采用不同折射率；致幻参数只放大色散，所有光色仍由同一波面决定。
vec3 dispersed_water(sampler2D terrain, vec2 source_pixel, vec2 offset_world, vec3 normal, float shore, vec2 texel) {
    vec3 center = safe_water_sample(terrain, source_pixel, offset_world + refracted_offset(normal, 1.333) * shore, texel);
    if (aurora_strength <= 0.0) {
        return center;
    }
    float red = safe_water_sample(terrain, source_pixel, offset_world + refracted_offset(normal, 1.333 - aurora_strength * 0.06) * shore, texel).r;
    float blue = safe_water_sample(terrain, source_pixel, offset_world + refracted_offset(normal, 1.333 + aurora_strength * 0.06) * shore, texel).b;
    return vec3(red, center.g, blue);
}

#include "res://shaders/adventure/wonderland/water_dream.gdshaderinc"

// 只绘制核心区，波面、流场和光学采样始终共用世界坐标。
void fragment() {
    vec2 source_pixel = tile_pixel_origin + UV / TEXTURE_PIXEL_SIZE;
    if (any(lessThan(source_pixel, core_pixel_rect.xy)) || any(greaterThanEqual(source_pixel, core_pixel_rect.zw))) {
        discard;
    }
    vec2 world_uv = source_pixel / (map_world_size * pixels_per_world);
    vec2 world_point = world_uv * map_world_size;
    vec3 region = clamp(texture(region_mask, world_uv).rgb, vec3(0.0), vec3(1.0));
    float region_weight = region.r;
    vec4 flow = texture(flow_field, world_uv);
    // 体色可以进入原运动安全带内的静水；岩石仍由完整湿域隔离，不扩张位移范围。
    float color_coverage = dream_strength > 0.0 && water_pattern != 2 ? region.g : 0.0;
    float coverage = max(region_weight, color_coverage);
    if (coverage <= 0.0 || effect_strength <= 0.0) {
        discard;
    }
    // 静止模式恢复原始水色，不残留冻结的彩色覆盖。
    vec3 water_rgb = texture(TEXTURE, UV).rgb;
    if (water_pattern != 2) {
        vec2 direction = flow.rg * 2.0 - 1.0;
        direction /= max(length(direction), 0.0001);
        // 两张图共享岸边衰减，取较小值避免重复相乘使窄河几乎完全静止。
        float shore = min(region_weight, clamp(flow.a, 0.0, 1.0));
        vec4 surface = wave_surface(world_point);
        // 双相输运交错半周期，回卷层的权重及导数同时为零。
        float phase_a = fract(water_angle / 6.28318530718);
        float phase_b = fract(phase_a + 0.5);
        float blend = 0.5 + 0.5 * cos(phase_a * 6.28318530718);
        vec2 travel = direction * amplitude_world * 1.5 * clamp(flow.b, 0.0, 1.0) * shore;
        // 原画俯视投影下适度放大波面坡度；所有光学效应仍共用这一法线。
        vec3 normal = normalize(vec3(-surface.xy * 6.0, 1.0));
        // 波高产生少量投影位移，连续输运则沿背景缓流搬运原始水纹。
        vec2 elevation_shift = vec2(0.0, -surface.z * 0.8) * shore;
        // 保留主菜单径向涟漪模式的折射入口；默认流动模式才进行双相输运。
        if (water_pattern == 1) {
            elevation_shift += water_surface_offset(world_point, wavelength_world) * amplitude_world * shore;
            travel = vec2(0.0);
        }
        vec3 layer_a = dispersed_water(TEXTURE, source_pixel, -travel * (phase_a - 0.5) + elevation_shift, normal, shore, TEXTURE_PIXEL_SIZE);
        vec3 layer_b = dispersed_water(TEXTURE, source_pixel, -travel * (phase_b - 0.5) + elevation_shift, normal, shore, TEXTURE_PIXEL_SIZE);
        float movement_coverage = region_weight / max(coverage, 0.00001);
        water_rgb = mix(water_rgb, mix(layer_a, layer_b, blend), movement_coverage);
        // 固定斜俯视下的Schlick反射率；没有随时间独立漂移的颜色图案。
        vec3 view_direction = normalize(vec3(0.0, -0.65, 0.76));
        vec3 light_direction = normalize(vec3(-0.25, 0.38, 0.89));
        vec3 transported = water_rgb;
        if (dream_strength > 0.0) {
            // 极光模式只走一套光学合成，水色与反射共享介质，不再调用旧薄膜叠加。
            water_rgb = dream_water_light(water_rgb, world_point, surface, normal,
                view_direction, light_direction, aurora_scale_world,
                phase_a, phase_b, blend, region.b * 64.0, shore * movement_coverage);
        }
        if (dream_strength < 0.12) {
            // 零强度沿用原水面；临近零值时短区间平滑交接，避免模式切换闪变。
            vec3 unified_color = water_rgb;
            water_rgb = transported;
            vec3 half_direction = normalize(view_direction + light_direction);
            float facing = max(dot(normal, view_direction), 0.0);
            float reflection = pow(max(dot(normal, half_direction), 0.0), 90.0);
            float fresnel = 0.0204 + 0.9796 * pow(1.0 - facing, 5.0);
            float energy = shimmer_strength / 0.045;
            // 同一折射落点映射产生焦散；色散只分开聚光边缘，不给整片水面染色。
            vec2 red_bend = refracted_offset(normal, 1.333 - aurora_strength * 0.06);
            vec2 blue_bend = refracted_offset(normal, 1.333 + aurora_strength * 0.06);
            vec2 green_bend = refracted_offset(normal, 1.333);
            vec3 caustic = vec3(wave_surface(world_point + (red_bend - green_bend) * 10.0).w, surface.w, wave_surface(world_point + (blue_bend - green_bend) * 10.0).w);
            // 放大光学起伏时同步放大Jacobian相对单位矩阵的变化，保持明暗与波面对应。
            caustic = vec3(1.0) / max(vec3(1.0) + 2.8 * (vec3(1.0) / max(caustic, vec3(0.4)) - vec3(1.0)), vec3(0.45));
            water_rgb *= vec3(1.0) + clamp(caustic - vec3(1.0), vec3(-0.5), vec3(1.0)) * 0.48 * energy * shore;
            water_rgb *= 1.0 + (dot(normal, light_direction) - light_direction.z) * 0.35 * energy * shore;
            // 平静天光仅由反射方向变化产生响应，保留原画的主要水色与明暗。
            vec3 reflected = reflect(-view_direction, normal);
            vec3 sky = mix(vec3(0.28, 0.47, 0.65), vec3(0.76, 0.87, 0.92), smoothstep(0.1, 0.9, reflected.z));
            water_rgb = mix(water_rgb, sky, clamp(fresnel * 1.5 * shore, 0.0, 0.22));
            water_rgb += vec3(0.74, 0.86, 0.91) * reflection * 0.09 * energy * shore;
            water_rgb = spectral_water_light(water_rgb, world_point, surface, normal,
                view_direction, light_direction, direction, aurora_scale_world,
                phase_a, phase_b, blend, clamp(flow.b, 0.0, 1.0), shore, surface.w);
            water_rgb = mix(transported, water_rgb, movement_coverage);
            water_rgb = mix(water_rgb, unified_color, smoothstep(0.0, 0.12, dream_strength));
        }
    }
    COLOR = vec4(clamp(water_rgb, vec3(0.0), vec3(1.0)), coverage * clamp(effect_strength, 0.0, 1.0));
}
