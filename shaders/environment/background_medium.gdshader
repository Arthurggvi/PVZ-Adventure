shader_type canvas_item;
render_mode unshaded;

// 背景已单独复制；单位和 UI 尚未绘制，远景可以柔化而不损失操作反馈。
uniform sampler2D screen_image : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D medium_field : filter_linear, repeat_disable;
uniform float strength = 0.0;
uniform float refraction_pixels = 1.6;
uniform float haze_strength = 0.085;
uniform vec3 haze_color : source_color = vec3(0.043, 0.149, 0.235);
uniform vec3 event_color : source_color = vec3(0.22, 0.75, 0.72);
// 事件退去后的微弱散射余辉，不改变逻辑或全局曝光。
uniform float afterglow = 0.0;
// 原图矩形随原版相机更新，近景船体与地面共处一层海水。
uniform vec4 board_rect = vec4(0.0, 0.1, 1.0, 0.9);

void fragment() {
    vec4 field = texture(medium_field, SCREEN_UV); // 连续低频密度及统一流光包络。
    vec2 art_uv = (SCREEN_UV - board_rect.xy) / board_rect.zw; // 当前观察位置对应的原画坐标。
    float far_depth = 1.0 - smoothstep(0.10, 0.96, art_uv.y); // 顶部远处更厚，底部近景仍保留轮廓。
    float ship = 1.0 - smoothstep(0.16, 0.24, art_uv.x); // 船体有更短的观察路径，并非完全排除在水体之外。
    float distance = mix(0.25 + far_depth * 0.95, 0.18 + far_depth * 0.40, ship); // 有限的二维艺术深度，不改棋盘坐标。
    vec2 pixel = vec2(1.0, SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x) / 1920.0; // 按参考宽度统一像素尺寸。
    vec2 offset = (field.rg - vec2(0.5)) * 2.0 * refraction_pixels * pixel
        * strength * mix(1.0, 0.35, ship) * (0.75 + field.a * 0.5); // 背景折射减半，船舷仍有极弱水感。
    vec2 uv = clamp(SCREEN_UV + offset, SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE); // 采样保持封闭。
    vec3 base = texture(screen_image, uv).rgb; // 原画清晰中心。
    vec2 radius = pixel * (1.0 + far_depth * 5.0); // 远景数像素柔焦，近景不铺大模糊。
    vec3 soft = base * 0.4; // 五点柔焦保留中心细节。
    soft += texture(screen_image, clamp(uv + radius, SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE)).rgb * 0.15;
    soft += texture(screen_image, clamp(uv - radius, SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE)).rgb * 0.15;
    soft += texture(screen_image, clamp(uv + radius * vec2(1.0, -1.0), SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE)).rgb * 0.15;
    soft += texture(screen_image, clamp(uv + radius * vec2(-1.0, 1.0), SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE)).rgb * 0.15;
    base = mix(base, soft, strength * (0.10 + far_depth * 0.48) * mix(1.0, 0.5, ship)); // 远景边缘先融入水，格线仍可定位。
    float optical_depth = haze_strength * (0.72 + field.b * 0.55) * distance * strength; // 密度决定透射，不用白色烟雾覆盖。
    vec3 water = haze_color * (0.85 + field.b * 0.35) + event_color * field.a * 0.035; // 蓝黑与浑浊青蓝之间的中间色。
    base = mix(water, base, exp(-optical_depth)); // 暗处提起水色、亮处降低对比，同时保留局部暖灯。
    vec3 glow = event_color * field.a * (0.14 + field.b * 0.38) * distance * strength; // 局部透光先显出浑浊水体，再随深度柔和消融。
    glow += haze_color * afterglow * distance * strength * 0.055; // 流光后缓慢恢复的极弱散射余辉。
    COLOR = vec4(vec3(1.0) - (vec3(1.0) - base) * exp(-glow), 1.0);
}
