## 邮差单张落地卡的独立战斗秒寿命与邮戳消散演出；从触地开始计时。
extends Control

## 自落地至失效正好 15 秒，不借用旧临时卡额外 5 秒闪烁宽限期。
const LIFETIME_SECONDS := 15.0
## 最后四秒逐渐显露倒计时邮戳与冷色纸张边光。
const WARNING_SECONDS := 4.0
## 卡片已失效后，仅保留不响应交互的短暂纸屑尾迹。
const VANISH_SECONDS := 0.36
const PAPER := Color("fff2d6")
const BLUE := Color("9ddbfa")
const INK := Color("344664")

## 所属真实卡片，成功种植时会随卡片离树一起释放。
var _card: Card
## 使用原生卡片管理器完成注销，不自行模拟种植信号。
var _manager: CardManager
## 每张卡自己计时；暂停菜单期间不递减。
var _remaining := LIFETIME_SECONDS
## 到期后纸屑的短演出进度。
var _vanish_age := 0.0
## 消除定时器、手持撤销和种植结算之间的重复销毁入口。
var _expired := false

## 入树之前绑定一次性种子包及其原生临时卡登记管理器。
func configure(card: Card, manager: CardManager) -> void:
	_card = card
	_manager = manager

## 不占用鼠标/触控；邮戳绘制跟随卡片本体的透视和飞行末姿态。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 5
	position = Vector2.ZERO
	size = _card.size
	set_process(true)

## 战斗暂停时自动停止。到期当天即注销，之后仅处理短纸屑残影。
func _process(delta: float) -> void:
	if _expired:
		_vanish_age += delta
		if _vanish_age >= VANISH_SECONDS:
			queue_free()
		else:
			queue_redraw()
		return
	if not is_instance_valid(_card) or _card.is_queued_for_deletion():
		queue_free()
		return
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining <= 0.0:
		_expire()
	else:
		queue_redraw()

## 种子包在精确寿命终点失效。手持时先撤销预览，再走原生用卡释放路径。
func _expire() -> void:
	if _expired:
		return
	_expired = true
	if not is_instance_valid(_card) or _card.is_queued_for_deletion():
		queue_free()
		return
	_card.is_can_click = false
	var hand: HandManager = _manager.main_game.hand_manager if is_instance_valid(_manager) 		and is_instance_valid(_manager.main_game) else null
	if is_instance_valid(hand) and is_instance_valid(hand.hm_character) 			and hand.hm_character.curr_card == _card:
		hand.curr_hm_status = HandManager.E_HandManagerStatus.Null
	# 清除手持时，管理器会恢复所有临时卡的鼠标过滤，必须最后再次禁用本卡。
	_card.mouse_filter_stop()
	# 离开卡片父节点后，即使最后一张派送卡销毁也能播完余光。
	var delivery: Node = _card.get_parent()
	var layer: Node = delivery.get_parent() if is_instance_valid(delivery) else null
	if is_instance_valid(layer):
		reparent(layer, true)
	else:
		queue_free()
	if is_instance_valid(_manager):
		_manager.card_use_end(_card)
	else:
		_card.queue_free()
	queue_redraw()

## 常驻细小邮戳显示剩余比例；临近到期才加重冷光提醒。
func _draw() -> void:
	if _expired:
		_draw_vanish()
		return
	var left: float = clampf(_remaining / LIFETIME_SECONDS, 0.0, 1.0)
	var urgent: float = 1.0 - clampf(_remaining / WARNING_SECONDS, 0.0, 1.0)
	var center := Vector2(size.x - 12.0, 12.0)
	draw_circle(center, 9.6, Color(INK, 0.55 + 0.22 * urgent), true, -1.0, true)
	draw_arc(center, 7.0, -PI * 0.5, -PI * 0.5 + TAU * left, 28,
		Color(PAPER.lerp(BLUE, urgent), 0.88), 1.8, true)
	draw_circle(center, 1.6, Color(PAPER, 0.90), true, -1.0, true)
	if urgent > 0.0:
		var pulse: float = 0.73 + 0.27 * sin((WARNING_SECONDS - _remaining) * TAU * 2.0)
		var bounds := Rect2(Vector2(1.5, 1.5), size - Vector2(3.0, 3.0))
		draw_rect(bounds, Color(BLUE, urgent * pulse * 0.65), false, 1.45, true)
		draw_arc(center, 10.5 + urgent * 3.0, 0.0, TAU, 28,
			Color(BLUE, urgent * pulse * 0.36), 1.4, true)

## 卡片已不可操作，仅留下短暂放射纸屑和向外收束的邮戳，不截屏复制卡面。
func _draw_vanish() -> void:
	var t: float = clampf(_vanish_age / VANISH_SECONDS, 0.0, 1.0)
	var fade: float = pow(1.0 - t, 2.0)
	var center: Vector2 = size * 0.5
	draw_arc(center, lerpf(10.0, 34.0, t), 0.0, TAU, 32,
		Color(BLUE, fade * 0.72), 2.0, true)
	for index: int in range(9):
		var heading: Vector2 = Vector2.from_angle(index * 2.39996)
		var tangent: Vector2 = heading.orthogonal()
		var origin: Vector2 = center + heading * (8.0 + t * (27.0 + float(index % 3) * 6.0))
		var length: float = (4.0 + float(index % 3) * 2.0) * (1.0 - t * 0.55)
		var corners := PackedVector2Array([
			origin + heading * length + tangent * 1.7,
			origin + tangent * 2.0,
			origin - heading * length * 0.8 - tangent * 1.4,
		])
		draw_colored_polygon(corners, Color(PAPER if index % 3 == 0 else BLUE, fade * 0.78))
