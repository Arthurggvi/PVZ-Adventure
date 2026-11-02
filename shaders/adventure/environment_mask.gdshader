// 环境贴图与整张背景共用设计坐标；动画只移动叠加层，不移动地形。
shader_type canvas_item;
// 真实背景空间内的当前位置、绘制尺寸及背景尺寸。
uniform vec2 origin = vec2(0.0);
uniform vec2 render_size = vec2(1.0);
uniform vec2 canvas_size = vec2(1920.0, 1080.0);
// RGB灰度蒙版与白色Alpha区域蒙版分别取对应通道。
uniform sampler2D region_mask : filter_linear, repeat_disable;
uniform bool alpha_channel = false;

void fragment() {
	vec2 map_uv = (origin + UV * render_size) / canvas_size;
	vec4 region = texture(region_mask, map_uv);
	float inside = step(0.0, map_uv.x) * step(map_uv.x, 1.0) * step(0.0, map_uv.y) * step(map_uv.y, 1.0);
	COLOR.a *= (alpha_channel ? region.a : region.r) * inside;
}
