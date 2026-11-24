## 救主的全屏黑闪。黑幕和冻结的抬掌余像画在战斗 HUD 上方。
extends Node2D

## 无垠、安乐与入场仪式共用覆盖 HUD 的黑幕。
enum Mode { NONE, QUICK, VOID, RITUAL }
## 读取原画当前帧，所有余像留在当时的屏幕位置。
const SilhouettePart = preload("res://scripts/battle/environment/battle_silhouette_part.gd")
## 抬掌已经展开后，保持完整画面供玩家看清手势，单位为战斗秒。
const LOOK_END := 0.18
## 世界和 HUD 完全落黑的时刻。
const DARK_AT := 0.58
## 先留出黑场的一拍，再触发无垠的判定。
const IMPACT_AT := 0.69
## 从封闭的黑场打开画面的时间窗口。
const REOPEN_AT := 0.92
## 无垠起手关键帧至演出结束的战斗秒数。
const VOID_END := 1.30
## 仪式的红柱开始下降后抬起黑幕，触地前恢复可见。
const RITUAL_REOPEN := 0.76
## 用来交接特写或触地的短复光尾段。
const RITUAL_END := 1.13
## 安乐沿用短停黑与快速回光，按不受倍速影响的真实秒计。
const QUICK_DARK := 0.13
## 安乐黑闪持续的真实秒数。
const QUICK_END := 0.32
## 余像的软边需要超出原画帧，单位为原画纹素。
const FRAME_PADDING := 28.0
## 已受理的黑场，包含发生时的原画快照、所属遭遇和一次结算。
class FlashRequest:
	## 无垠所属的遭遇，仪式用零。
	var group: int
	## 采样不到纹理时为空，仍保留全黑帧的结算。
	var imprint: SilhouettePart
	## 落黑后交给所属遭遇的结算入口。
	var impact: Callable

	## [param id] 标识遭遇，[param frame] 是出手时的快照，[param resolve] 在黑场调用一次。
	func _init(id: int, frame: SilhouettePart, resolve: Callable) -> void:
		group = id
		imprint = frame
		impact = resolve
## 沿同一画布铺满主视口的黑幕。
@export var veil: ColorRect
## 当前在播的闪屏类型。
var _mode: Mode = Mode.NONE
## 自抬掌关键帧经过的演出秒数。
var _elapsed := 0.0
## 正在落黑的仪式或无垠判定；快速闪屏为空。
var _current: FlashRequest
## 多个救主同轮出招时排队保留后续无垠的独立结算。
var _pending_voids: Array[FlashRequest] = []
## 原画帧的局部矩形。没有有效帧时仍会正常黑闪。
var _frame := Rect2()
## 本场独占的余像材质。
@onready var _material := material as ShaderMaterial

## 暂停界面接管画面时收起黑幕，关闭暂停后从原进度继续。
func _enter_tree() -> void:
	TreePauseManager.pause_factors_changed.connect(_refresh_overlay)

## 旧画布离树后，返回地图时清空暂停标记无需再刷新它。
func _exit_tree() -> void:
	TreePauseManager.pause_factors_changed.disconnect(_refresh_overlay)

## 安乐的快速闪屏立即盖住本帧上的转换。活动中的无垠优先。
func play_quick() -> void:
	if _mode == Mode.VOID or _mode == Mode.RITUAL:
		return
	_mode = Mode.QUICK
	_elapsed = 0.0
	_refresh_overlay()

## 为 [param group] 在 [param pose] 的实际出手帧定格余像，落黑后调用 [param impact]。
func play_void(group: int, pose: AnimatedSprite2D, impact: Callable) -> void:
	var request := FlashRequest.new(group, _snapshot(pose), impact) # 排队时原演员仍在抬掌；出队时允许其已退场。
	if _mode == Mode.VOID or _mode == Mode.RITUAL:
		_pending_voids.append(request)
		return
	_begin_long_flash(Mode.VOID, request)

## 从 [param pose] 采样黑闪余像，落黑后调用 [param impact]。等待上一段黑闪结束时返回 false。
func play_ritual(pose: AnimatedSprite2D, impact: Callable) -> bool:
	if _mode != Mode.NONE:
		return false
	_begin_long_flash(Mode.RITUAL, FlashRequest.new(0, _snapshot(pose), impact))
	return true

## 在 [param mode] 下呈现 [param request] 的原画并保留它的落黑结算。
func _begin_long_flash(mode: Mode, request: FlashRequest) -> void:
	_elapsed = 0.0
	_mode = mode
	_current = request
	_apply_imprint(request.imprint)
	_refresh_overlay()

## 撤销 [param group] 的全部未结算无垠。已开始落黑时保留自然消退。
func cancel_void(group: int) -> void:
	for index: int in range(_pending_voids.size() - 1, -1, -1): # 撤销属于同一遭遇的所有待播判定。
		if _pending_voids[index].group == group:
			_pending_voids.remove_at(index)
	if _mode != Mode.VOID or _current.group != group:
		return
	_current.impact = Callable()
	if _elapsed <= LOOK_END:
		_finish_flash()

## 战斗结束时收走遮挡，避免压住胜负演出。
func stop() -> void:
	_pending_voids.clear()
	if _mode == Mode.NONE:
		return
	_finish_flash()

## 清空当前画面，正常结束后交接给下一位等待中的施法者。
func _finish_flash() -> void:
	_mode = Mode.NONE
	_current = null
	_refresh_overlay()
	while not _pending_voids.is_empty():
		var next: FlashRequest = _pending_voids.pop_front() # 演员离场不会取消存活分身的判定。
		if next.impact.is_valid():
			_begin_long_flash(Mode.VOID, next)
			break

## [param delta] 是无垠使用的战斗秒数，[param real_seconds] 是安乐的未暂停真实秒数。
func advance(delta: float, real_seconds: float) -> void:
	if _mode == Mode.NONE:
		return
	var previous: float = _elapsed # 落黑与结算分帧，掉帧时也先完整呈现黑幕。
	_elapsed += real_seconds if _mode == Mode.QUICK else delta
	if _current != null and _current.impact.is_valid():
		if previous < DARK_AT and _elapsed >= DARK_AT:
			_elapsed = DARK_AT
		elif _elapsed >= IMPACT_AT:
			_elapsed = IMPACT_AT
			var resolve: Callable = _current.impact # 先清空请求，受击和死亡回调不能让判定重入。
			_current.impact = Callable()
			resolve.call()
	var end: float = QUICK_END if _mode == Mode.QUICK else (RITUAL_END if _mode == Mode.RITUAL else VOID_END) # 不同黑闪沿用对应的恢复时间。
	if _elapsed >= end:
		_finish_flash()
	else:
		_refresh_overlay()

## 冻结 [param source] 的原画、镜像及屏幕变换；快照不绑定该节点的生存期。
func _snapshot(source: AnimatedSprite2D) -> SilhouettePart:
	if not is_instance_valid(source):
		return null
	var part := SilhouettePart.new(source) # 共用动态投影的帧读取与翻转规则。
	if not part.read_frame():
		return null
	part.pose = source.get_global_transform_with_canvas()
	part.sprite = null
	return part

## 将 [param part] 的屏幕快照写入本场材质；没有纹理时仅关闭余像。
func _apply_imprint(part: SilhouettePart) -> void:
	if part == null:
		_frame = Rect2()
		return
	_frame = Rect2(part.rect.position, part.rect.size.abs())
	var sheet: Texture2D = part.texture # 余像直接采样现有原画图集。
	var area: Rect2 = part.source # 在图集内限制滤波，避免引入相邻动作帧。
	if sheet is AtlasTexture:
		area = sheet.region
		sheet = sheet.atlas
	var texels: Vector2 = sheet.get_size() # 换算到安全的半纹素边界。
	var lo: Vector2 = (area.position + Vector2(0.5, 0.5)) / texels # 第一枚纹素中心。
	var span: Vector2 = (area.size - Vector2.ONE) / texels # 最后一枚纹素中心前的跨度。
	transform = get_canvas_transform().affine_inverse() * part.pose
	_material.set_shader_parameter(&"pose_sheet", sheet)
	_material.set_shader_parameter(&"pose_source", Vector4(lo.x, lo.y, span.x, span.y))
	_material.set_shader_parameter(&"pose_rect", Vector4(_frame.position.x, _frame.position.y, _frame.size.x, _frame.size.y))
	_material.set_shader_parameter(&"flip_axes", Vector2(float(part.rect.size.x < 0.0), float(part.rect.size.y < 0.0)))
	queue_redraw()

## 将亮手势后的渐暗、停黑和复光应用到整个屏幕，再在黑幕上画出灰色余像。
func _refresh_overlay() -> void:
	var cover: float = 0.0 # 非演出期间不提交全屏黑幕。
	var imprint: float = 0.0 # 安乐只使用黑幕。
	if not get_tree().paused or (_mode == Mode.RITUAL and TreePauseManager.is_paused_for(TreePauseManager.E_PauseFactor.SaviorCinematic)):
		if _mode == Mode.QUICK:
			cover = 1.0 - smoothstep(QUICK_DARK, QUICK_END, _elapsed)
		elif _mode == Mode.VOID or _mode == Mode.RITUAL:
			var reopen: float = RITUAL_REOPEN if _mode == Mode.RITUAL else REOPEN_AT # 受击黑场先完成，再为光柱让出画面。
			var end: float = RITUAL_END if _mode == Mode.RITUAL else VOID_END # 和出队时机一致。
			cover = smoothstep(LOOK_END, DARK_AT, _elapsed) * (1.0 - smoothstep(reopen, end, _elapsed))
			imprint = smoothstep(0.47, 0.61, _elapsed) * (1.0 - smoothstep(0.66, 1.16, _elapsed))
	veil.visible = cover > 0.0
	if veil.visible:
		veil.color.a = cover
	visible = imprint > 0.0 and _frame.has_area()
	if visible:
		_material.set_shader_parameter(&"imprint_strength", imprint)
		_material.set_shader_parameter(&"imprint_age", smoothstep(0.52, 1.16, _elapsed))

## 扩出原画之外的少量余量，允许灰影的边缘逐渐溶开。
func _draw() -> void:
	if _frame.has_area():
		draw_rect(_frame.grow(FRAME_PADDING), Color.WHITE)
