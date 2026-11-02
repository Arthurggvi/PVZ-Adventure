// 锁定关卡仅对当前按钮图片灰显，不修改原始贴图及子节点文字。
shader_type canvas_item;

void fragment() {
	// 按视觉亮度转为灰度并轻度压暗，保留透明边缘。
	COLOR.rgb = vec3(dot(COLOR.rgb, vec3(0.299, 0.587, 0.114))) * 0.75;
}
