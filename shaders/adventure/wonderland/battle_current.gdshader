shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/adventure/wonderland/current_light.gdshaderinc"
#include "res://shaders/adventure/wonderland/battle_board_sampling.gdshaderinc"

// 波高控制纵向折射和浪脊体积，零值保留原水面。
uniform float wave_strength : hint_range(0.0, 2.0) = 1.0;
// 天空原图只读复用，供波面反射采样。
uniform sampler2D sky_texture : source_color, filter_linear, repeat_disable;
// 行界由权威棋盘换算到原图UV，种植与浪峰共用原图边界。
uniform float row_edges[7];
// 调制色与原纹理分开，防止片元默认COLOR重复乘入原图。
varying vec4 sprite_tint;

void vertex() {
    sprite_tint = COLOR;
    VERTEX.x *= 1.0 + right_extension; // 仅扩展绘制范围，原版预览容器不随美术缩放。
}

// 船、礁石、水母原画内衰减折射，保留干燥船身和前景轮廓。
float open_sea(vec2 uv) {
    float ship_edge = 0.141 - 0.069 * smoothstep(0.50, 0.84, uv.y); // 船尾随高度收窄。
    float ship = smoothstep(ship_edge, ship_edge + 0.019, uv.x); // 船侧软过渡。
    float reef = 1.0 - smoothstep(0.86, 1.0, uv.y) * (1.0 - smoothstep(0.08, 0.17, uv.x)); // 左下珊瑚。
    float jelly = 1.0 - 0.90 * smoothstep(0.78, 0.94, uv.x) * smoothstep(0.68, 0.87, uv.y); // 右下水母。
    return ship * reef * jelly * smoothstep(0.01, 0.10, uv.y);
}

void fragment() {
    vec2 uv = board_art_uv(UV); // 保护区始终使用原图坐标。
    vec2 p = vec2(uv.x * 1.7768, uv.y); // 原图比例校正。
    float sea = mix(open_sea(uv), 1.0, smoothstep(1.0, 1.10, uv.x)); // 右侧续接开阔水域，不重复水母保护区。
    float distance_detail = smoothstep(0.04, 0.23, uv.y); // 远海向天空柔和衔接。
    float signed_edge = uv.y - row_edges[0]; // 最近行界的有向距离，用于浪峰前后两面。
    float edge_index = 0.0; // 最近的原图浪峰序号。
    float lane_position = (uv.y - row_edges[0]) / (row_edges[1] - row_edges[0]); // 超出棋盘时连续外推。
    for (int i = 0; i < 7; i++) { // 原图七道横向格界构成固定的主浪脊。
        if (abs(uv.y - row_edges[i]) < abs(signed_edge)) {
            signed_edge = uv.y - row_edges[i];
            edge_index = float(i);
        }
        if (i < 6 && uv.y >= row_edges[i]) {
            lane_position = float(i) + (uv.y - row_edges[i]) / (row_edges[i + 1] - row_edges[i]);
        }
    }
    float edge_distance = abs(signed_edge); // 原图格线距离。
    float grid_lock = smoothstep(0.002, 0.014, edge_distance); // 格界处收回折射，种植视觉不漂移。

    vec2 flow = vec2(0.0, -motion.y * 4.0 / 6.28318530718); // 仅沿纵向的持续流动。
    float bed = current_flow_noise(p * vec2(4.0, 9.0) + flow, vec2(16.0, 4.0)); // 连贯宽幅水流。
    float detail = current_flow_noise(p * vec2(19.0, 37.0) + flow * 2.0, vec2(64.0, 8.0)); // 水下柔和次级细节。
    float large_color = current_flow_noise(p * vec2(2.0, 3.0) + vec2(0.0, -motion.w * 4.0 / 6.28318530718), vec2(8.0, 4.0)); // 更慢的整片色流。
    float travel = lane_position * 6.28318530718 - motion.x * 2.0; // 波谷内垂直推进，波前平行于格界。
    float rolling = sin(travel) * 0.72 + sin(travel * 2.0 + bed * 1.2) * 0.17; // 主纵浪和附着的小浪。
    vec2 offset = vec2(0.0003 * (bed - 0.5), rolling * 0.0055 + (detail - 0.5) * 0.0015); // 主位移严格沿纵向。
    float crest_fold = (current_noise(vec2(uv.x * 28.0, edge_index * 2.0 + sin(motion.x) * 0.6)) - 0.5) * 0.005; // 峰顶围绕格界轻微翻卷，不产生横向推进。
    vec2 displacement = offset * grid_lock + vec2(0.0, crest_fold * exp(-edge_distance * 130.0)); // 默认峰顶位移不超过1.34屏幕像素。
    vec2 refracted_uv = clamp(uv + displacement * sea * wave_strength * distance_detail,
        TEXTURE_PIXEL_SIZE * 0.5, vec2(1.0 + right_extension, 1.0) - TEXTURE_PIXEL_SIZE * 0.5); // 原图和右缘延展使用同一连续坐标。
    vec4 original = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0))); // 保留船体原色和原画透明度。
    if (uv.x > 1.0) {
        original = mix(original, texture(TEXTURE, board_art_continuation_uv(uv)), smoothstep(1.0, 1.10, uv.x));
    }
    vec3 water = texture(TEXTURE, clamp(refracted_uv, vec2(0.0), vec2(1.0))).rgb; // 连续水面折射。
    if (refracted_uv.x > 1.0) {
        water = mix(water, texture(TEXTURE, board_art_continuation_uv(refracted_uv)).rgb, smoothstep(1.0, 1.10, refracted_uv.x));
    }

    float crest_breath = 0.5 + 0.5 * sin(motion.x * 2.0 - edge_index * 0.45); // 沿纵向依次涌起的格界浪峰。
    float crest_width = 0.008 + 0.004 * crest_breath + 0.002 * bed; // 呼吸只改变浪面宽度，中心始终贴格界。
    float folded_edge = signed_edge + crest_fold * wave_strength; // 反射与折射共用一条微起伏峰顶。
    float crest = exp(-pow(folded_edge / crest_width, 2.0)); // 连续横向主浪峰。
    float forward_face = exp(-pow((folded_edge + crest_width) / (crest_width * 1.7), 2.0)); // 迎光的宽浪坡。
    float back_face = exp(-pow((folded_edge - crest_width * 1.8) / (crest_width * 1.9), 2.0)); // 浪峰后的深蓝背坡。
    float trough = sin(fract(lane_position) * 3.14159265359); // 每格中心为波谷。
    float volume = 0.92 - trough * 0.12 - back_face * 0.16 + rolling * 0.028 + bed * 0.06; // 波峰到波谷的连贯体积。
    water *= mix(1.0, volume, wave_strength * distance_detail);

    vec3 spectral = current_spectrum(uv.x, large_color * 1.6 + uv.y * 2.0); // 宽幅青紫粉金随洋流交融。
    vec3 reflection = texture(sky_texture, clamp(vec2(uv.x + (bed - 0.5) * 0.012,
        0.78 - uv.y * 0.36 + rolling * 0.028), vec2(0.01), vec2(0.99))).rgb; // 同方向纵浪调制天空倒影。
    float foam = current_noise(vec2(uv.x * 88.0, folded_edge * 360.0 + sin(motion.x) * 0.7)); // 只附着于峰顶的柔和水沫。
    float face_texture = current_flow_noise(p * vec2(27.0, 110.0) + flow * 3.0, vec2(64.0, 12.0)); // 细节限于浪坡，不铺满水面。
    float ripple_phase = uv.y * 370.0 + bed * 4.0 - motion.x * 4.0; // 依附大浪的纵向涟漪，沿横向连续。
    float ripples = pow(0.5 + 0.5 * sin(ripple_phase + detail * 0.7), 5.0); // 光纹集中在涟漪迎光面。
    float core = exp(-abs(folded_edge) * 900.0); // 原图格界附近的微起伏亮芯。
    float crest_light = crest * (0.12 + 0.14 * crest_breath + 0.28 * face_texture) + forward_face * (0.09 + 0.11 * face_texture); // 宽峰与细节属于同一浪面。
    vec3 light = spectral * (0.028 + bed * 0.065 + detail * 0.025); // 格内保留平静水体与低对比聚光。
    light += mix(spectral, reflection, 0.22) * crest_light * distance_detail; // 彩色宽浪脊。
    light += mix(spectral, vec3(0.44, 0.94, 0.92), 0.35) * core * (0.10 + 0.14 * foam); // 沿格界自然汇聚的峰顶高光。
    light += spectral * pow(0.5 + 0.5 * cos(travel), 3.0) * 0.055 * grid_lock * distance_detail; // 波谷中的弱纵向流光。
    light += spectral * ripples * (0.032 + forward_face * 0.17 + crest * 0.12) * distance_detail; // 连贯细浪只在主浪坡上清晰显现。
    light += spectral * smoothstep(0.30, 0.85, large_color) * (0.07 + bed * 0.10) * distance_detail; // 宽幅有色水体连接各道浪峰。

    float beam_x = 0.55 + 0.03 * sin(motion.z); // 天空与海面共用日光位置。
    float sun_path = exp(-pow((uv.x - beam_x) / (0.045 + uv.y * 0.18), 2.0)); // 近景逐渐展开的暖色光路。
    light += vec3(1.0, 0.69, 0.32) * sun_path * (crest_light + core * 0.2) * 0.30 * exp(-uv.y * 1.5);
    water = current_expose(water, light * wave_strength);
    vec3 result = mix(original.rgb, water, sea); // 船侧、珊瑚与水母使用连续衰减过渡。

    float lantern = exp(-length((uv - vec2(0.133, 0.255)) * vec2(1.7768, 1.0)) * 60.0); // 船灯局部暖光。
    result = current_expose(result, vec3(1.0, 0.52, 0.13) * lantern * (0.21 + 0.06 * sin(motion.x * 2.0)));
    float jelly_glow = exp(-length((uv - vec2(0.925, 0.86)) * vec2(1.6, 1.0)) * 16.0); // 水母与下缘洋流的冷光。
    result = current_expose(result, current_spectrum(uv.x, 2.0) * jelly_glow * (0.07 + 0.05 * sin(motion.y)));
    float feather = mix(0.022, 0.122, smoothstep(0.136, 0.22, uv.x)); // 沿用海天接缝和桅杆保护。
    COLOR = vec4(result, original.a * smoothstep(0.0, feather, uv.y)) * sprite_tint;
}
