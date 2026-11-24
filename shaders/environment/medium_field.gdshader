shader_type canvas_item;
render_mode unshaded, blend_disabled;
#include "res://shaders/adventure/wonderland/current_light.gdshaderinc"

// 按真实时间采样，与声画事件导演共用时钟。
uniform float clock_seconds = 0.0;
// xy 为流光运动方向，z 为进度，w 为包络强度。
uniform vec4 current_event = vec4(0.0);
// 当前光场的宽度与横向偏移。
uniform vec2 event_shape = vec2(0.42, 0.0);
// 地板原画在视口中的范围，使中景水雾与环境流光保持场景空间位置。
uniform vec4 board_rect = vec4(0.0, 0.1, 1.0, 0.9);

void fragment() {
    vec2 art_uv = (UV - board_rect.xy) / board_rect.zw; // 原版镜头移动只改变观察位置。
    vec2 p = art_uv * vec2(3.8, 2.3); // 低频空间尺度，不随格子或单位数量变化。
    vec2 drift = vec2(clock_seconds * 0.006, -clock_seconds * 0.004); // 水雾远慢于折射，保持沉重而非烟雾翻滚。
    float a = current_fbm(p + drift); // 第一方向的介质密度。
    float b = current_fbm(p * 1.17 + vec2(8.3, 2.4) - drift * 0.71); // 不同速度的第二方向。
    vec2 flow = vec2(a, b); // RG 储存连续二维位移场。
    float haze = current_fbm(p * 0.65 + vec2(b, a) * 0.35 + drift * 0.28); // B 储存更低频的薄雾。
    float passage = dot(art_uv - vec2(0.5), current_event.xy) - mix(-1.0, 1.0, current_event.z) + event_shape.y; // 宽光场横越场景，与地板同空间。
    float width = event_shape.x * (0.75 + haze * 0.5); // 云气使光场轮廓不规则。
    float opening = smoothstep(0.28, 0.72, a); // 宽幅云隙使明暗形成连续层次，不铺满均匀光幕。
    float light = exp(-pow(passage / width, 2.0)) * (0.18 + 1.4 * opening * opening) * current_event.w; // A 储存照亮局部水体的柔光遮罩。
    COLOR = vec4(flow, haze, light);
}
