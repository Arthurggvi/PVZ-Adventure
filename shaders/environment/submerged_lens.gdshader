shader_type canvas_item;
render_mode unshaded;

// 95 层读取完整战场、卡槽、头像、菜单与波次；100 层正式切场遮幕继续独立。
uniform sampler2D screen_image : hint_screen_texture, filter_linear, repeat_disable;
// 与 CPU 点击逆映射共用四个有界相位，禁止使用 Shader TIME。
uniform vec4 lens_phase = vec4(0.0);
// xy 为两轴 UV 位移幅度，已包含阶段权重与同一洋流事件。
uniform vec2 lens_amplitude = vec2(0.0);
// 入水色散及镜头边沿的厚介质强度。
uniform float immersion = 0.0;
uniform float current_energy = 0.0;

// 与 BattleEnvironmentLens.screen_to_source 保持逐项一致；边界衰减保证不会漏出空白。
vec2 source_uv(vec2 uv) {
    vec2 q = uv + vec2(sin(uv.y * 5.0 + lens_phase.z) * 0.045, cos(uv.x * 4.0 - lens_phase.w) * 0.04);
    float x = sin(q.y * 12.0 + lens_phase.x + sin(q.x * 5.0 + lens_phase.z) * 0.55) * 0.58
        + sin(q.y * 26.0 - lens_phase.y + q.x * 3.0) * 0.26
        + sin(q.x * 8.0 + q.y * 5.0 + lens_phase.w) * 0.16;
    float y = sin(q.x * 10.0 - lens_phase.y + cos(q.y * 4.0 + lens_phase.w) * 0.45) * 0.58
        + cos(q.x * 21.0 + lens_phase.z - q.y * 4.0) * 0.24 + cos(q.y * 7.0 + lens_phase.x) * 0.18;
    vec2 edge = smoothstep(vec2(0.0), vec2(0.055), uv) * smoothstep(vec2(0.0), vec2(0.055), vec2(1.0) - uv);
    return clamp(uv + vec2(x, y) * lens_amplitude * edge, vec2(0.0), vec2(1.0));
}

void fragment() {
    vec2 uv = source_uv(SCREEN_UV); // 以同一个完整画面折射，界面不会像贴在水面外。
    vec2 bend = uv - SCREEN_UV; // 弯曲较强的部位才产生极小色散。
    vec2 fringe = bend * 0.065; // 红、蓝光的路径稍有不同，文字保留清晰绿色主通道。
    vec3 scene = texture(screen_image, uv).rgb;
    scene.r = texture(screen_image, clamp(uv + fringe, SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE)).r;
    scene.b = texture(screen_image, clamp(uv - fringe, SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE)).b;
    float edge_depth = smoothstep(0.22, 0.67, length((SCREEN_UV - vec2(0.5)) * vec2(1.0, 0.85))); // 镜头周围的深水压力。
    scene *= mix(vec3(1.0), vec3(0.90, 0.97, 1.0), immersion * (0.20 + edge_depth * 0.30)); // 深度主要由前序水体散射承担，不再统一压黑。
    scene *= 1.0 - edge_depth * immersion * 0.045;
    vec3 scatter = vec3(0.035, 0.38, 0.48) * current_energy * immersion * (0.012 + edge_depth * 0.024); // 同次流光穿过眼前的水层。
    COLOR = vec4(vec3(1.0) - (vec3(1.0) - scene) * exp(-scatter), 1.0);
}
