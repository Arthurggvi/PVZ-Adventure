// 辉夜星系：冷色体积星云、暗部衬底、三条有纹理的发光旋臂；只覆盖云气本身。
shader_type canvas_item;
render_mode unshaded, blend_mix;

// 可暂停战斗秒数，不读取全局TIME。
uniform float age = 0.0;
// 场的完整寿命，末尾0.42秒与真实星核一同坍缩。
uniform float lifetime = 3.0;
// 0为完整，1和2减少噪声细节与烟雾光量。
uniform int quality = 0;
// 保留宿主淡出和颜色调制。
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

// 无纹理二维散列，避免像素级正弦随机数的高成本。
float hash21(vec2 p) {
	vec2 v = fract(p * vec2(123.34, 456.21)); // 空间格点散列。
	v += dot(v, v + 45.32);
	return fract(v.x * v.y);
}

// 平滑值噪声，不引入额外图片或全屏采样。
float noise21(vec2 p) {
	vec2 cell = floor(p); // 整数格点。
	vec2 local = fract(p); // 格内坐标。
	vec2 ease = local * local * (3.0 - 2.0 * local); // 连续边缘插值。
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), ease.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0, 1.0)), ease.x), ease.y);
}

// 有界三层细节，最低画质省略最细一层。
float nebula(vec2 p) {
	float cloud = noise21(p) * 0.58 + noise21(p * 2.07 + vec2(8.4, 2.6)) * 0.28; // 体积团块与中等细节。
	if (quality < 2) {
		cloud += noise21(p * 4.13 + vec2(3.2, 11.7)) * 0.14;
	}
	return cloud;
}

// 预乘透明度叠色，冷色星云在明亮草地仍保留饱和度与深度。
vec4 layer(vec4 back, vec3 ink, float opacity) {
	float alpha = clamp(opacity, 0.0, 1.0); // 每层覆盖率有界。
	return vec4(ink * alpha + back.rgb * (1.0 - alpha), alpha + back.a * (1.0 - alpha));
}

void fragment() {
	vec2 q = (UV - vec2(0.5)) * 2.0; // UV直接映射棋盘格距。
	float opening = 1.0 - pow(1.0 - clamp(age / 0.43, 0.0, 1.0), 3.0); // 成臂前气体先绽开。
	float collapse_t = clamp((age - (lifetime - 0.42)) / 0.42, 0.0, 1.0); // 与星核相同的退场区间。
	float collapse = 1.0 - collapse_t * collapse_t * collapse_t * (collapse_t * (collapse_t * 6.0 - 15.0) + 10.0); // 五次曲线匹配真实星核。
	vec2 p = q / vec2(0.95, 0.78) / max(opening * collapse, 0.025); // 三臂纵横比例匹配命中几何。
	float radius = length(p); // 星系归一化半径。
	float angle = atan(p.y, p.x); // 星系极角。
	float wind = 0.30 * max(0.0, age - 0.07); // 与真实星核一致的缓慢公转。
	float theta = angle - radius * 3.35 - wind; // 每120度一条旋臂。
	vec2 flow = vec2(cos(angle - wind + radius * 2.8), sin(angle - wind + radius * 2.8)) * (radius * 9.0 + 1.1); // 气体域沿旋臂扭曲。
	float clouds = nebula(flow + vec2(age * 0.25, -age * 0.37)); // 连续细密的星云质感。
	float detail = noise21(flow * 3.7 + vec2(-age * 0.55, age * 0.21)); // 纤维与不均匀亮斑。
	float arm_distance = abs(sin(theta * 1.5 + (clouds - 0.5) * 1.35)); // 气团宽度独立于星核轨道，湍流令三瓣星云不再像细风车。
	float width = 0.34 + (1.0 - radius) * 0.31 + clouds * 0.25; // 臂宽由气团自然变化。
	float arm = exp(-pow(arm_distance / max(width, 0.035), 2.4)); // 中心到外缘柔和衰减。
	float spine = exp(-pow((arm_distance - 0.23 - detail * 0.09) / 0.12, 2.0)); // 更细的冷蓝明亮脊线。
	float outer = 1.0 - smoothstep(0.66, 0.98, radius); // 外缘稀薄并透明。
	float inner = smoothstep(0.015, 0.10, radius); // 核周围留出层次。
	float structure = arm * outer * inner; // 不在旋臂外铺整片雾。
	float knots = smoothstep(0.25, 0.82, clouds); // 云团实体密度。
	float wisps = pow(clamp(clouds + detail * 0.40, 0.0, 1.0), 1.35); // 纤维纹理的局部反差。
	vec3 gas = mix(vec3(0.12, 0.045, 0.38), vec3(0.43, 0.16, 0.88), smoothstep(0.22, 0.73, clouds)); // 星云阴影呈深靛紫。
	gas = mix(gas, vec3(0.15, 0.70, 0.93), smoothstep(0.55, 0.88, clouds + sin(theta * 3.0 + radius * 8.0) * 0.13)); // 蓝绿电离气体。
	vec4 result = vec4(0.0); // 只按气团本身叠加透明度。
	result = layer(result, vec3(0.018, 0.015, 0.09), structure * (0.24 + knots * 0.28)); // 薄暗底使草地上的颜色不泛白。
	result = layer(result, gas, structure * (0.38 + wisps * 0.54));
	result = layer(result, vec3(0.31, 0.73, 0.96), spine * outer * inner * wisps * 0.48); // 冷蓝高光随云气断续。
	float lane = exp(-pow(sin(theta * 1.5 + 0.16 + clouds * 0.28) / 0.105, 2.0)); // 深紫尘带在宽气团内部弯曲穿行。
	result = layer(result, vec3(0.034, 0.018, 0.13), lane * structure * wisps * 0.35);
	float core = exp(-radius * radius * 63.0); // 精小星系核，避免白色大圆盘。
	float core_halo = exp(-radius * radius * 22.0); // 蓝紫低量光晕。
	result = layer(result, vec3(0.17, 0.16, 0.54), core_halo * 0.39);
	result = layer(result, vec3(0.56, 0.78, 1.0), core * 0.90);
	float pin = exp(-radius * radius * 620.0); // 银白色尖核。
	result = layer(result, vec3(0.94, 0.98, 1.0), pin * 0.96);
	vec2 flare_axis = vec2(p.x * 0.988 + p.y * 0.156, -p.x * 0.156 + p.y * 0.988); // 恒星核的两条轻微倾斜衍射芒。
	float flare = exp(-pow(flare_axis.x / 0.20, 2.0) - pow(flare_axis.y / 0.008, 2.0)) + exp(-pow(flare_axis.x / 0.007, 2.0) - pow(flare_axis.y / 0.13, 2.0)); // 细芒局限于中央十余像素。
	result = layer(result, vec3(0.72, 0.87, 1.0), flare * 0.53);
	float onset = smoothstep(0.02, 0.24, age); // 不抢命中闪光的第一拍。
	float ending = smoothstep(0.0, 0.23, lifetime - age); // 坍缩终点同时熄灭。
	float edge = 1.0 - smoothstep(0.92, 1.0, length(q)); // 画布四周始终透明。
	float crowd = quality == 2 ? 0.76 : 1.0; // 多银河叠加时约束总光量。
	COLOR = vec4(result.rgb / max(result.a, 0.001), min(result.a, 0.65 + pin * 0.32) * onset * ending * edge * crowd) * tint;
}
