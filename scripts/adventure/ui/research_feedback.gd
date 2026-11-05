## 研究操作的屏幕结果提示。接收已确定的结果并播放动效，不参与操作校验或资产修改。
extends Control

## 提示条沿用背包和研究室的贴图、文字样式。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 提示条的原始尺寸，包含两行结果说明的空间。
const BANNER_SIZE := Vector2(640, 128)
## 响应窗口大小的定位层，动效只修改其子节点。
var _anchor: Control
## 承载提示素材和文字的动画节点。
var _banner: Control
## 按结果切换绿金与红色的九宫格底板。
var _plate: NinePatchRect
## 成功星标或失败提示标记。
var _symbol: TextureRect
## 失败标记的感叹号，用形状区分成功与失败。
var _alert: Label
## 操作名称与成功、失败状态。
var _heading: Label
## 失败原因或操作结算说明。
var _detail: Label
## 当前播放的提示动画，连续操作时由最新结果接管。
var _motion: Tween

## 初始化全屏定位层和可重复使用的提示条。
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	_anchor = Control.new()
	_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_anchor)
	_banner = Control.new()
	_banner.size = BANNER_SIZE
	_banner.pivot_offset = BANNER_SIZE * 0.5
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.hide()
	_anchor.add_child(_banner)
	_plate = Art.panel(_banner, "buttons/action_confirm_normal.png", Vector2.ZERO, BANNER_SIZE, 22)
	_symbol = Art.image(_banner, "overlays/star_filled.png", Vector2(26, 34), Vector2(60, 60))
	_alert = Art.label(_banner, "!", Vector2(26, 34), Vector2(60, 60), 34, Color("fff4d6"))
	_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading = Art.label(_banner, "", Vector2(106, 14), Vector2(506, 42), 30, Color("fff0cb"))
	_detail = Art.label(_banner, "", Vector2(106, 59), Vector2(506, 53), 21, Color("fff0cb"))
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resized.connect(_fit)
	_fit()

## 播放 [param heading] 和 [param detail] 的屏幕提示。[param succeeded] 决定弹入或短震动效。
func present(heading: String, detail: String, succeeded: bool) -> void:
	if is_instance_valid(_motion):
		_motion.kill()
	_heading.text = heading
	_detail.text = detail
	_plate.texture = Art.texture("buttons/action_confirm_normal.png" if succeeded else "buttons/action_danger_normal.png")
	_symbol.texture = Art.texture("overlays/star_filled.png" if succeeded else "icons/notification.png")
	_alert.visible = not succeeded
	_banner.position = Vector2(0, 16)
	_banner.scale = Vector2.ONE * 0.94
	_banner.modulate.a = 0.0
	_banner.show()
	_motion = create_tween().set_parallel(true)
	_motion.tween_property(_banner, "modulate:a", 1.0, 0.16)
	_motion.tween_property(_banner, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if succeeded:
		_motion.tween_property(_banner, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_motion.tween_property(_banner, "scale", Vector2.ONE, 0.18)
		_motion.chain().tween_property(_banner, "position:x", -8.0, 0.05)
		_motion.chain().tween_property(_banner, "position:x", 6.0, 0.07)
		_motion.chain().tween_property(_banner, "position:x", 0.0, 0.08).set_ease(Tween.EASE_OUT)
	_motion.chain().tween_interval(1.55 if succeeded else 2.1)
	_motion.chain().tween_property(_banner, "modulate:a", 0.0, 0.26)
	_motion.parallel().tween_property(_banner, "position:y", -14.0, 0.26)
	_motion.chain().tween_callback(_banner.hide)

## 窗口尺寸变化时，提示仍在屏幕上方居中，且整体等比缩放。
func _fit() -> void:
	if not is_instance_valid(_anchor) or size.x <= 0.0 or size.y <= 0.0:
		return
	var factor: float = minf(1.4, minf(size.x / 1600.0, size.y / 900.0)) # 小窗口缩小提示条，大窗口限制最大宽度。
	_anchor.scale = Vector2.ONE * factor
	_anchor.position = Vector2(size.x * 0.5, size.y * 0.24) - BANNER_SIZE * factor * 0.5
