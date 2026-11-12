// 重映射阳光贴图的颜色，保留光芒、亮芯以及收集动画的透明度。
shader_type canvas_item;

// 阳光轮廓、主体和高光的色值，由生产者的外观提供。
uniform vec4 edge_color : source_color;
uniform vec4 main_color : source_color;
uniform vec4 highlight_color : source_color;

// 保存父级淡出和各片动画原有的颜色乘数。
varying vec4 sprite_tint;

void vertex() {
	sprite_tint = COLOR;
}

void fragment() {
	// 原图的亮度区分轮廓和光芒，蓝通道区分暖黄色主体与近白高光。
	vec4 source = texture(TEXTURE, UV);
	float brightness = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	float main_weight = smoothstep(0.60, 0.94, brightness);
	float highlight_weight = smoothstep(0.46, 0.92, source.b) * main_weight;
	vec3 rgb = mix(edge_color.rgb, main_color.rgb, main_weight);
	COLOR = vec4(mix(rgb, highlight_color.rgb, highlight_weight), source.a) * sprite_tint;
}
