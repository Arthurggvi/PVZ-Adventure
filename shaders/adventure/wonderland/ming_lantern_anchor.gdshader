// 巨锚的水线在世界坐标内固定，锚身进入水下时逐渐被水面遮没。
shader_type canvas_item;
render_mode unshaded;

// 锚尖真实触地的世界高度。
uniform float surface_y = 0.0;
// 触地后是否开始应用水线和浅层水色。
uniform bool immersed = false;
// 从锚尖碰地开始经过的战斗秒数。
uniform float contact_time = 0.0;
// 随不同落点变化的细小水面起伏。
uniform float phase = 0.0;

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 metal = COLOR; // 原画的蓝紫金属反光保持在纹理内。
	float runup = 1.0 - smoothstep(0.0, 0.62, contact_time); // 刚被砸过的水线稍微起伏，随后变平。
	float ripple = sin(world_position.x * 0.072 + phase - contact_time * 18.0) * (1.5 + runup * 4.0)
		+ sin(world_position.x * 0.114 + phase * 0.64 + contact_time * 11.0) * 1.55; // 水线的两种起伏。
	float depth = world_position.y - (surface_y + ripple); // 为正时位于水线以下。
	float wetness = smoothstep(-6.0, 12.0, depth) * float(immersed); // 水下的锚体暂时透出暗蓝色。
	float visible = 1.0 - smoothstep(-0.7, 23.0, depth) * float(immersed); // 深处锚身被水逐步遮住。
	float seam = exp2(-depth * depth * 0.15) * float(immersed) * (0.62 + 0.38 * runup); // 水线附近的一条很薄的泡沫反光。
	vec3 color = metal.rgb * mix(vec3(0.80, 0.87, 0.94), vec3(0.33, 0.57, 0.64), wetness); // 金属轮廓在入水前保持较沉的色调。
	color = mix(color, vec3(0.59, 0.81, 0.82), seam * 0.34);
	COLOR = vec4(color, metal.a * visible);
}
