shader_type canvas_item;

// 标签图按实际帧的局部坐标读取，邻接碎片完整重建当前画帧。
uniform sampler2D fracture_ids : filter_nearest, repeat_disable;
uniform vec4 frame_uv;
uniform float piece_id;

void fragment() {
	vec2 local_uv = (UV - frame_uv.xy) / frame_uv.zw;
	float id = texture(fracture_ids, local_uv).r * 255.0;
	if (abs(id - piece_id) > 0.5) {
		discard;
	}
}
