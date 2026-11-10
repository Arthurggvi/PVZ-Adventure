shader_type canvas_item;
render_mode unshaded;

uniform sampler2D light_field : source_color, filter_linear;
uniform vec2 sample_pixel = vec2(0.00188, 0.00333);
uniform float blur_radius = 2.5;
uniform float threshold = 0.10;

void fragment() {
    vec2 uv = UV;
    // 在已经提取独立发光信息的光场上做 13 个低分辨率 Gaussian 近似采样。
    vec3 sum = vec3(0.0);
    vec2 dx = vec2(sample_pixel.x * blur_radius, 0.0);
    vec2 dy = vec2(0.0, sample_pixel.y * blur_radius);
    sum += texture(light_field, uv).rgb * 0.20;
    sum += (texture(light_field, uv + dx).rgb + texture(light_field, uv - dx).rgb) * 0.105;
    sum += (texture(light_field, uv + dy).rgb + texture(light_field, uv - dy).rgb) * 0.105;
    sum += (texture(light_field, uv + dx + dy).rgb + texture(light_field, uv - dx - dy).rgb) * 0.075;
    sum += (texture(light_field, uv + dx - dy).rgb + texture(light_field, uv - dx + dy).rgb) * 0.075;
    sum += (texture(light_field, uv + dx * 2.0).rgb + texture(light_field, uv - dx * 2.0).rgb) * 0.035;
    sum += (texture(light_field, uv + dy * 2.0).rgb + texture(light_field, uv - dy * 2.0).rgb) * 0.035;
    COLOR = vec4(max(sum - vec3(threshold), vec3(0.0)), 1.0);
}
