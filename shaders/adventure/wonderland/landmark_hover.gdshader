shader_type canvas_item;
render_mode unshaded, blend_add;
// 地区只提供悬停光，不拥有点击或关卡状态；轻暖加光保留底图与水面的原有颜色。
uniform vec4 accent : source_color = vec4(1.0, 0.97, 0.90, 1.0);
// 强度由宿主的显式时间渐入渐出，不额外读取全局 TIME。
uniform float strength : hint_range(0.0,1.0) = 0.0;
uniform float effect_seconds = 0.0;
// 蒙版像素与世界单位的比例，保证不同裁切尺寸的内轮廓拥有相同世界宽度。
uniform vec2 mask_pixels_per_world = vec2(1.0);
uniform float contour_width_world : hint_range(0.1, 3.0) = 1.15;

// 裁切之外按透明处理，避免边缘采样延展成贴图矩形；输入始终是 L8 的红通道。
float region_at(sampler2D mask_texture, vec2 mask_uv) {
    if (any(lessThan(mask_uv, vec2(0.0))) || any(greaterThan(mask_uv, vec2(1.0)))) {
        return 0.0;
    }
    return texture(mask_texture, mask_uv).r;
}

void fragment() {
    float region_alpha = region_at(TEXTURE, UV);
    // 八方向等半径内缩，从同一份羽化轮廓取得柔和内沿，不向区域之外画光晕。
    vec2 ring_step = TEXTURE_PIXEL_SIZE * mask_pixels_per_world * contour_width_world;
    vec2 diagonal_step = ring_step * 0.70710678;
    float inner_alpha = region_alpha;
    inner_alpha = min(inner_alpha, region_at(TEXTURE, UV + vec2(ring_step.x, 0.0)));
    inner_alpha = min(inner_alpha, region_at(TEXTURE, UV - vec2(ring_step.x, 0.0)));
    inner_alpha = min(inner_alpha, region_at(TEXTURE, UV + vec2(0.0, ring_step.y)));
    inner_alpha = min(inner_alpha, region_at(TEXTURE, UV - vec2(0.0, ring_step.y)));
    inner_alpha = min(inner_alpha, region_at(TEXTURE, UV + diagonal_step));
    inner_alpha = min(inner_alpha, region_at(TEXTURE, UV - diagonal_step));
    inner_alpha = min(inner_alpha, region_at(TEXTURE, UV + vec2(diagonal_step.x, -diagonal_step.y)));
    inner_alpha = min(inner_alpha, region_at(TEXTURE, UV + vec2(-diagonal_step.x, diagonal_step.y)));
    float contour = region_alpha * smoothstep(0.0, 0.8, region_alpha - inner_alpha);
    // 区域内部只加少量近白光，边沿略强；缓慢的小幅呼吸不会盖住底图的明暗与色彩。
    float breathe = 0.975 + 0.025 * sin(effect_seconds * 1.6);
    float light_alpha = (0.018 * region_alpha + 0.075 * contour) * strength * breathe;
    COLOR = vec4(accent.rgb, accent.a * light_alpha);
}
