## 名牌悬停/键盘焦点反馈；作为原按钮子节点，不接管点击或玩家档案逻辑。
extends Node

## 悬停时从牌面中心轻微放大，避免明显移动点击区域。
const HOVER_SCALE := 1.035
## 暖色提亮牌面与子文字，不生成额外提示框。
const HOVER_TINT := Color(1.12, 1.08, 1.0, 1.0)
## 原有按钮继续管理点击、音效与按下位移。
var button: BaseButton
## 场景初始缩放，移出或隐藏时恢复。
var resting_scale: Vector2
## 场景初始调制，不覆盖原有主题颜色。
var resting_tint: Color
## 只保留一个绑定按钮生命周期的过渡动画。
var feedback_tween: Tween

## 在原按钮上连接反馈，保留已有脚本、信号及用户名子节点。
func _ready() -> void:
	button = get_parent() as BaseButton
	resting_scale = button.scale
	resting_tint = button.modulate
	button.pivot_offset = button.size / 2.0
	button.mouse_entered.connect(_refresh)
	button.mouse_exited.connect(_refresh)
	button.focus_entered.connect(_refresh)
	button.focus_exited.connect(_refresh)
	button.visibility_changed.connect(_refresh)

## 悬停或焦点时提亮并平滑放大；快速移入移出不会叠加Tween。
func _refresh() -> void:
	if feedback_tween != null:
		feedback_tween.kill()
	if not button.is_visible_in_tree():
		button.scale = resting_scale
		button.modulate = resting_tint
		return
	var active := not button.disabled and (button.is_hovered() or button.has_focus()) # 不给禁用牌增加反馈。
	feedback_tween = button.create_tween().set_parallel(true)
	feedback_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	feedback_tween.tween_property(button, "scale", resting_scale * (HOVER_SCALE if active else 1.0), 0.16)
	feedback_tween.tween_property(button, "modulate", resting_tint * (HOVER_TINT if active else Color.WHITE), 0.16)

## 子组件单独移除时也还原按钮，不留下仍运行的过渡。
func _exit_tree() -> void:
	if feedback_tween != null:
		feedback_tween.kill()
	if is_instance_valid(button):
		button.scale = resting_scale
		button.modulate = resting_tint
