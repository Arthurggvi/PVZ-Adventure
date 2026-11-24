shader_type canvas_item;

#include "res://shaders/adventure/wonderland/garden_airship_cloud_light.gdshaderinc"

// 原画草皮外界，保持铜边、挂点与平台轮廓不变。
const vec2 TURF_START = vec2(0.16, 0.157);
const vec2 TURF_END = vec2(0.84, 0.718);
// 甲板资源选定的静态变体。只改变草皮内少量花点的位置和颜色。
uniform float variation = 0.0;
// 长桥只有云影，基础材质沿用其原画。
uniform float turf_lighting = 1.0;

varying vec4 sprite_color;
varying vec2 world_point;

void vertex() {
	sprite_color = COLOR;
	world_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 start = step(TURF_START, UV); // 是否进入草皮左上边界。
	vec2 end = step(UV, TURF_END); // 是否尚未离开草皮右下边界。
	float turf = start.x * start.y * end.x * end.y; // 保留全部装饰和外部透明区。
	vec2 grid_uv = (UV - TURF_START) / (TURF_END - TURF_START); // 两行两列的草皮坐标。
	vec2 tile = fract(grid_uv * 2.0); // 当前格内从 0 到 1 的像素位置。
	vec2 edge = min(tile, 1.0 - tile); // 当前格四条边界的保留距离。
	float interior = smoothstep(0.09, 0.28, min(edge.x, edge.y)) * turf; // 只重排格内纹理。
	vec2 source = UV + vec2(0.045, -0.029) * interior * variation; // 靠近缝线时回到原图。
	vec4 texel = texture(TEXTURE, source); // 保留原画 alpha 和羽化边缘。
	vec3 lighting = mix(vec3(1.0), vec3(1.024, 1.0, 0.971), turf * turf_lighting); // 晴日暖光，只施加于草皮。
	float tone = 1.0 - 0.028 * variation * interior; // 静态变体的轻微草皮明度差。
	COLOR = vec4(texel.rgb * lighting * tone * airship_cloud_light(world_point), texel.a) * sprite_color;
}
