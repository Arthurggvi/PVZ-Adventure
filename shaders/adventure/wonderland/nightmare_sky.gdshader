shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/adventure/wonderland/nightmare_light.gdshaderinc"

// 天空独立调制，不将默认纹理颜色重复乘到曝光结果上。
varying vec4 sprite_tint;

void vertex() {
    sprite_tint = COLOR;
}

void fragment() {
    vec2 cloud_uv = nightmare_cloud_uv(UV); // 原图暗云以独立深度缓慢翻卷。
    vec3 cloud = texture(TEXTURE, cloud_uv).rgb; // 保留原画的云层边缘与笔触。
    float cracks = smoothstep(0.035, 0.32, cloud.g - cloud.r * 0.8); // 只点亮原画已有的青色裂隙。
    float cloud_opening = current_fbm(UV * vec2(5.0, 3.0) + vec2(sin(motion.z) * 0.7, cos(motion.y) * 0.6)); // 天空独立的大尺度云隙。
    float breath = 0.18 + smoothstep(0.34, 0.73, cloud_opening) * 0.60 + ambient_energy * 0.20; // 缓慢呼吸与洋流事件柔和叠加。
    vec3 light = vec3(0.035, 0.64, 0.77) * cracks * breath * 0.55; // 只照亮天空原画云缝，不向地面拖动光源。
    float abyss_color = 0.5 + 0.5 * sin(motion.w * 0.5 + cloud_uv.x * 2.0); // 深蓝、黑蓝和暗海青之间极慢的局部色移。
    cloud *= mix(vec3(1.0), mix(vec3(0.70, 0.82, 0.94), vec3(0.68, 0.97, 0.96), abyss_color), abyss_strength);
    COLOR = vec4(current_expose(cloud, light), 1.0) * sprite_tint;
}
