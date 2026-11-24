## 资源单次加载超过三秒后才出现的一行静态说明，不改变原有进度条布局。
## 只消费资源活动快照，不轮询磁盘、更新业务状态或产生动态特效。
extends Label

## 仅当某个资源真实执行超过三秒才允许显示。
const THRESHOLD_MSEC := 3_000
## 紧凑版放在进度条上方的固定空白处；全屏放在草皮下方。
var _compact := false

## 根据 [param compact] 将文字安放在原进度条周围，不盖住取消按钮。
func configure(compact: bool) -> void:
	_compact = compact
	position = Vector2(-145, -41) if compact else Vector2(-190, 157)
	size = Vector2(290, 23) if compact else Vector2(380, 25)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 14 if compact else 15)
	add_theme_color_override("font_color", Color("675840") if compact else Color("e2dfc2"))
	add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.45) if not compact else Color.TRANSPARENT)
	add_theme_constant_override("shadow_offset_y", 1 if not compact else 0)

## [param activity] 仅包含当前资源路径和真实毫秒；每帧最多更新一行文本。
func present(activity: Dictionary) -> void:
	var elapsed: int = int(activity.get("elapsed_msec", 0)) # 空活动即表示没有正在执行的资源。
	var path: String = str(activity.get("path", ""))
	var active: bool = not path.is_empty() and elapsed >= THRESHOLD_MSEC
	if not active:
		visible = false
		return
	var caption: String = path.get_file() # 玩家只看文件名，完整路径留在诊断报告。
	var next_text: String = "正在加载 · %s · %.1fs" % [caption, float(elapsed) / 1000.0]
	if text != next_text:
		text = next_text
	visible = true
