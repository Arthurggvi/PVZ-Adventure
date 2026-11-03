shader_type canvas_item;

// 临时叶片纹理形变，不是分离树冠或物理摆动；只改变遮罩内纹理采样，不移动顶点。
uniform sampler2D leaf_region_mask : filter_linear, repeat_disable;
// 取实际源纹理尺寸；全图UV与遮罩归一化UV一一对应。
uniform vec2 artwork_pixels = vec2(1920.0, 1080.0);
uniform float amplitude_pixels : hint_range(0.0, 5.0) = 2.0;
uniform float wind_speed : hint_range(0.0, 3.0) = 0.65;
uniform bool wind_enabled = false;
// 保留原有调制，不重复乘贴图Alpha。
varying vec4 tint;

void vertex() {
    tint = COLOR;
}

void fragment() {
    float influence = texture(leaf_region_mask, UV).r;
    float t = TIME * wind_speed;
    vec2 pixel_offset = vec2(
        sin(t + UV.y * 28.0 + UV.x * 11.0),
        0.26 * cos(t * 0.73 + UV.x * 19.0)
    ) * amplitude_pixels * influence * (wind_enabled ? 1.0 : 0.0);
    vec2 source_uv = clamp(UV + pixel_offset / artwork_pixels, vec2(0.0), vec2(1.0));
    // 源采样同样受遮罩约束，避免把相邻天空、树干或建筑拖入叶片。
    source_uv = mix(UV, source_uv, texture(leaf_region_mask, source_uv).r);
    COLOR = texture(TEXTURE, source_uv) * tint;
}
