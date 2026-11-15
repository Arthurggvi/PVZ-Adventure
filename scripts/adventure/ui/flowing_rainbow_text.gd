## 为羊皮纸面板上的文字提供可复用的流动彩色填充。
extends RefCounted

## 按字形内的像素位置与引擎时间计算颜色。
const RAINBOW_SHADER = preload("res://shaders/adventure/flowing_rainbow_text.gdshader")

## 为 [param label] 的字形启用流动色带。[param highlight_strength] 是扫光强度，范围为 0 到 1。
## 文本与布局由调用方配置，本方法替换字体填色和阴影以及标签的材质。
static func apply_to(label: Label, highlight_strength: float) -> void:
	var material := ShaderMaterial.new() # 各标签可独立选择扫光强度，共用着色器和时钟。
	material.shader = RAINBOW_SHADER
	material.set_shader_parameter("highlight_strength", highlight_strength)
	label.material = material
	label.add_theme_color_override("font_color", Color.WHITE) # 白色保留着色器生成的填色。
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT) # 扫光只绘制在文字笔画内。
