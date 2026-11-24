shader_type canvas_item;
render_mode unshaded, blend_mix;

#include "res://shaders/environment/battle_shadow_atlas.gdshaderinc"
#include "res://shaders/environment/battle_shadow_ground.gdshaderinc"

uniform float penumbra_scale = 0.76;
varying vec2 lamp_uv;
varying float penumbra_texels;

void vertex() {
	GroundVertex projected = project_ground_vertex(INSTANCE_ID, UV);
	VERTEX = projected.position;
	pose_uv = projected.pose_uv;
	lamp_uv = projected.lamp_uv;
	penumbra_texels = projected.penumbra_texels;
	shadow_data = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	// 顶点可能超出局部灯格，禁止写入相邻灯的遮挡。
	if (any(lessThan(lamp_uv, vec2(0.0))) || any(greaterThan(lamp_uv, vec2(1.0)))) {
		discard;
	}
	float center = silhouette_coverage(pose_uv);
	float width = clamp(penumbra_texels * penumbra_scale, 0.0, 1.15);
	if (width > 0.15) {
		vec2 edge = vec2(width / 48.0, 0.0);
		center = 0.54 * center + 0.23 * (silhouette_coverage(pose_uv + edge) + silhouette_coverage(pose_uv - edge));
	}
	// 同一盏灯的交叠剪影以 Alpha 并集合并。
	COLOR = vec4(vec3(1.0), smoothstep(0.10, 0.74, center) * shadow_data.b);
}
