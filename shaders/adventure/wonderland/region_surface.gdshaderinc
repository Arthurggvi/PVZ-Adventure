// 原地形图块的统一世界采样；核心半开裁切避免留边区域重复合成。
uniform sampler2D region_mask : filter_linear, repeat_disable;
uniform vec2 mask_origin_world;
uniform vec2 mask_extent_world;
uniform vec2 tile_pixel_origin;
uniform float pixels_per_world = 4.6178;
uniform vec4 core_pixel_rect;
uniform float effect_seconds = 0.0;
uniform float period_seconds = 9.0;
uniform float effect_strength = 0.5;
uniform float amplitude_world = 0.0;
uniform float event_weight = 0.0;
uniform int style = 0;
uniform vec2 center_world;
uniform vec2 radii_world;

vec4 local_mask(vec2 world) {
    vec2 uv = (world-mask_origin_world)/mask_extent_world;
    if (any(lessThan(uv,vec2(0.0))) || any(greaterThanEqual(uv,vec2(1.0)))) { return vec4(0.0); }
    return texture(region_mask,uv);
}

bool outside_core(vec2 pixel) {
    return pixel.x < core_pixel_rect.x || pixel.y < core_pixel_rect.y || pixel.x >= core_pixel_rect.z || pixel.y >= core_pixel_rect.w;
}
