shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/adventure/wonderland/battle_board_sampling.gdshaderinc"
#include "res://shaders/adventure/wonderland/nightmare_light.gdshaderinc"

// 由噩梦棋盘换算到原图的七条行界和十条列界。
uniform float row_edges[7];
uniform float column_edges[10];

// 调制色与纹理分开，避免右侧延展重复乘入未换算的原图采样。
varying vec4 sprite_tint;

void vertex() {
    sprite_tint = COLOR;
    VERTEX.x *= 1.0 + right_extension;
}

// 此层保留陆地的权威格位；最终整屏透镜统一折射战场、实体和 UI。
void fragment() {
    vec2 uv = board_art_uv(UV); // 与普通阶段使用同一原图坐标映射。
    vec4 original = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0))); // 原图及选卡延展保持稳定。
    if (uv.x > 1.0) {
        original = mix(original, texture(TEXTURE, board_art_continuation_uv(uv)), smoothstep(1.0, 1.10, uv.x));
    }
    float ground = smoothstep(0.17, 0.22, uv.x); // 船体不受地面云影及裂缝光影响。
    float feather = mix(0.014, 0.14, smoothstep(0.19, 0.27, uv.x)); // 上缘仍沿用原图拼接。
    float cloud = current_fbm(uv * vec2(5.0, 3.0) + vec2(sin(motion.z) * 1.5, cos(motion.y) * 0.8)); // 宽幅云影。
    float fine_cloud = current_fbm(uv * vec2(11.0, 7.0) + vec2(sin(motion.y) * 0.6, -sin(motion.z))); // 依附于大云影的软边。
    float bounce = 0.16 + ambient_energy * 0.12; // 事件只轻推环境底光，不再用天幕位置投射地面聚光。
    vec3 surface = original.rgb * (1.0 + ground * 0.16) * (1.0 - ground * smoothstep(0.42, 0.72, cloud) * 0.20); // 保留原画和深浅云影，局部亮点形成反差。
    vec3 light = vec3(0.0); // 地面光全部在原图 UV 中生成，随原版相机移动。
    float row_distance = 2.0; // 最近的权威行界距离。
    float column_distance = 2.0; // 最近的权威列界距离。
    float row_index = 0.0; // 最近行界编号，供光沿格网传播。
    float column_index = 0.0; // 最近列界编号。
    for (int i = 0; i < 7; i++) { // 逐条读取权威行界。
        float distance_y = abs(uv.y - row_edges[i]); // 原图行界距离。
        if (distance_y < row_distance) {
            row_distance = distance_y;
            row_index = float(i);
        }
    }
    for (int i = 0; i < 10; i++) { // 逐条读取权威列界。
        float distance_x = abs(uv.x - column_edges[i]) * 1.7768; // 按原图长宽比统一线宽。
        if (distance_x < column_distance) {
            column_distance = distance_x;
            column_index = float(i);
        }
    }
    float board = ground * (1.0 - smoothstep(column_edges[9], column_edges[9] + 0.04, uv.x))
        * smoothstep(row_edges[0] - 0.03, row_edges[0], uv.y) * (1.0 - smoothstep(row_edges[6], row_edges[6] + 0.03, uv.y)); // 只照亮实际棋盘。
    float seam_distance = min(row_distance, column_distance); // 十字裂隙共用光场。
    float source_crack = smoothstep(0.012, 0.10, original.g - original.r * 0.8); // 原画上的裂纹决定亮边细节。
    float travel = pow(0.5 + 0.5 * sin(uv.x * 7.0 + uv.y * 5.0 - motion.x + cloud * 2.0), 3.0); // 沿整片裂隙缓慢传递的能量。
    float seam = exp(-seam_distance * 180.0) * source_crack * (0.025 + travel * 0.035) * (0.55 + fine_cloud * 0.45); // 格子主要通过原画色差辨认，避免把棋盘描成发光网格。
    float point_energy = nightmare_point_energy(vec2(column_index, row_index)); // 原图交点身份决定各自错开的随机呼吸。
    float distance_squared = row_distance * row_distance + column_distance * column_distance; // 等比例的局部光斑距离。
    float core = exp(-distance_squared * 180000.0); // 极小的青白亮核。
    float near_glow = exp(-distance_squared * 4500.0); // 附近柔和但明亮的海青光。
    float far_glow = exp(-distance_squared * 650.0) * (1.0 - smoothstep(0.035, 0.055, sqrt(distance_squared))); // 淡远晕在相邻交点区域前平滑消失。
    float spill = exp(-row_distance * 700.0 - column_distance * 50.0)
        + exp(-column_distance * 700.0 - row_distance * 60.0); // 沿两条原画裂缝向外泄光。
    vec3 point_light = vec3(0.10, 0.65, 0.72) * core * 0.22
        + vec3(0.025, 0.74, 0.82) * (near_glow * 0.18 + far_glow * 0.20 + spill * source_crack * 0.035) * (0.65 + fine_cloud * 0.35); // 压低十字星芒，光主要消融在局部水体中。
    light += (vec3(0.025, 0.78, 0.84) * seam + point_light * point_energy) * board;
    light += vec3(0.025, 0.35, 0.45) * (0.045 + source_crack * (0.12 + cloud * 0.32)) * bounce * ground; // 云纹和大面积地面一起承接散光，明暗呼吸不只停在格线。
    float edge = smoothstep(0.76, 1.0, uv.y) + smoothstep(0.87, 1.04, uv.x) * 0.5; // 薄雾集中在棋盘外沿。
    float mist = smoothstep(0.34, 0.75, fine_cloud) * edge * ground; // 大片低矮云气，留出格内可读区域。
    light += vec3(0.025, 0.30, 0.43) * mist * (0.12 + bounce * 0.20);
    float lantern_breath = 0.90 + 0.06 * sin(motion.x * 9.0) + 0.04 * sin(motion.y * 13.0); // 船灯温和的不等频烛火。
    float lantern = exp(-length((uv - vec2(0.121, 0.367)) * vec2(1.7768, 1.0)) * 52.0); // 灯笼灯罩局部暖光。
    float window = exp(-length((uv - vec2(0.047, 0.439)) * vec2(1.7768, 1.0)) * 43.0); // 船舱窗光。
    float deck = exp(-dot((uv - vec2(0.105, 0.565)) / vec2(0.050, 0.028), (uv - vec2(0.105, 0.565)) / vec2(0.050, 0.028))); // 甲板上的狭长暖色投影。
    light += vec3(1.0, 0.44, 0.09) * (lantern * 0.19 + window * 0.12 + deck * 0.07) * lantern_breath;
    COLOR = vec4(current_expose(surface, light), original.a * smoothstep(0.0, feather, uv.y)) * sprite_tint;
}
