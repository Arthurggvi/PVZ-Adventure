## 检查实际绘制的海滨背景，供冷启动和回城复用。
extends RefCounted

## 用归一化坐标覆盖天际线、左侧建筑、广场和港口，不依赖窗口尺寸。
const REGIONS := {
	"天际线": Rect2(0.53, 0.02, 0.44, 0.23),
	"建筑": Rect2(0.04, 0.23, 0.30, 0.47),
	"广场": Rect2(0.24, 0.47, 0.45, 0.47),
	"港口": Rect2(0.75, 0.24, 0.22, 0.42),
}
## 每个区域沿两轴均匀取样，避免全尺寸逐像素遍历。
const SAMPLES_PER_AXIS := 12
## 许可午夜画面与平台色差，同时拒绝接近纯色或只残留局部描边的区域。
const MIN_LUMA_SPAN := 0.04
## 16 单元的 Compatibility Canvas 仅为本场景留出第 1 至 8 号材质纹理槽。
const MAX_MATERIAL_SAMPLERS := 8

## [param frame] 为揭幕后不含 UI 的实际合成帧。返回首个失败原因，成功返回空字符串。
static func error_for(frame: Image) -> String:
	if frame == null or frame.is_empty():
		return "城镇未输出有效画面"
	var image_size := Vector2(frame.get_size()) # UV 到读回纹理像素的比例。
	for name: String in REGIONS: # 各区独立成立，少量正常像素不能掩盖其余区域白屏。
		var region: Rect2 = REGIONS[name] # 当前区域的采样边界。
		var luma := PackedFloat32Array() # 亮度分布用于排除零星轮廓与像素噪点。
		for y in range(SAMPLES_PER_AXIS): # 当前区域内的采样行。
			for x in range(SAMPLES_PER_AXIS): # 当前区域内的采样列。
				var offset := (Vector2(x, y) + Vector2(0.5, 0.5)) / SAMPLES_PER_AXIS # 取网格中心。
				var pixel := Vector2i((region.position + region.size * offset) * image_size) # 实际帧中的采样像素。
				luma.append(frame.get_pixelv(pixel).get_luminance())
		luma.sort()
		var tail := floori(luma.size() * 0.1) # 忽略两端各一成的极亮和极暗像素。
		var span := luma[luma.size() - 1 - tail] - luma[tail] # 稳健的区域亮度跨度，范围为 0 至 1。
		if span < MIN_LUMA_SPAN:
			return "城镇%s区域缺少明暗细节（亮度跨度 %.3f）" % [name, span]
	return ""

## [param host] 为已完成绘制的城镇合成宿主。逐材质检查引擎报告的本地采样器声明。
## 有超限材质时返回首个节点及用量。通过时返回空字符串。
static func sampler_budget_error(host: Node) -> String:
	for item: CanvasItem in host.find_children("*", "CanvasItem", true, false): # 包含各离屏视口内运行时创建的绘制节点。
		var material := item.material as ShaderMaterial # 当前绘制节点直接使用的材质。
		if material == null or material.shader == null:
			continue
		var samplers := 0 # 本次绘制占用的自定义纹理槽数。
		for uniform: Dictionary in material.shader.get_shader_uniform_list(): # 引擎解析 include 后提供的本地声明。
			if uniform.type == TYPE_OBJECT:
				samplers += 1
			elif uniform.type == TYPE_ARRAY:
				return "城镇材质 %s 的数组 %s 需按元素核对纹理槽预算" % [host.get_path_to(item), uniform.name]
		if samplers > MAX_MATERIAL_SAMPLERS:
			return "城镇材质 %s 占用 %d 个自定义纹理槽，Compatibility 预算为 %d" % [host.get_path_to(item), samplers, MAX_MATERIAL_SAMPLERS]
	return ""
