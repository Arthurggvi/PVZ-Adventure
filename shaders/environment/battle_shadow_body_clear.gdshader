shader_type canvas_item;
render_mode unshaded, blend_mix;

#include "res://shaders/environment/battle_shadow_atlas.gdshaderinc"

// 光场内部的一次低分辨率屏幕复制，R 保留当前批次无遮挡的光强。
uniform sampler2D incident_light : hint_screen_texture, filter_nearest, repeat_disable;

void vertex() {
	shadow_data = INSTANCE_CUSTOM.rgb;
	pose_uv = VERTEX * 0.5 + vec2(0.5);
}

void fragment() {
	float coverage = smoothstep(0.03, 0.67, silhouette_coverage(pose_uv));
	vec2 light = textureLod(incident_light, SCREEN_UV, 0.0).rg;
	// 角色挡在地面投影前，R/G 原样合并，只恢复 B 的入射光。
	COLOR = vec4(light, light.r, coverage);
}
