## 三张真实卡牌共享一次邮件派送，落地后交回原生手持与一次性用卡流程。
extends Control

## Cut-in 退场附近开始投递，以下演出时序均为实际秒。
const LAUNCH: float = 1.04
## 中、左、右的出发间隔。
const STAGGER: float = 0.13
## 每张卡主飞行段的基础时长。
const FLIGHT: float = 0.64
## 留给最后一枚印记的余光；结束后停止逐帧绘制。
const DURATION: float = 2.48
## 三张卡的目标横向比例，先落中央再向两侧打开。
const LANES := [0.50, 0.24, 0.76]
## 首选纵向比例，中心落得稍深，形成错落布局。
const DEPTHS := [0.63, 0.39, 0.47]
## 中、左、右各自的出发倾角，单位弧度。
const TILTS := [-0.16, -0.36, 0.34]
## 纸张、信封边线及雨蓝色流光的调色板。
const PAPER := Color("fff2d6")
## 信件与场景明暗之间的深蓝轮廓。
const INK := Color("344664")
## 飞行边光与落地印记共用的雨蓝。
const BLUE := Color("9ddbfa")
## 单张邮件抵达后的独立计时与邮戳消散，不借用通用临时卡的 5 秒宽限期。
const ParcelExpiry = preload("res://scripts/adventure/skills/rainy_postman_parcel_expiry.gd")

## 卡片及其飞行只在原战局、原轮次和原阶段有效。
var _battle: RepeaterShotContext
## 已经完整准备的三张真实卡；消费后保留原数组序号供其余动画使用。
var _cards: Array[Card] = []
## 三个落点在可见棋盘范围内的归一化坐标，窗口变化时重新投影。
var _landings := PackedVector2Array()
## 每张卡的旋转幅度，小幅度使星级和植物图仍可辨认。
var _bank := PackedFloat32Array()
## 已登记到卡片管理器的索引，同一张卡只启用一次。
var _delivered: Dictionary[int, bool] = {}
## 正常消费和阶段清理共用的剩余卡数。
var _live: int = 0
## 可见棋盘与视口安全边距的交集，以 UI 坐标表示。
var _field: Rect2
## 卡片出信封的位置。
var _origin: Vector2
## 小视口下的等比演出缩放。
var _fit: float = 1.0
## 从施放时起累计的动画秒，结束后固定在最终姿态。
var _age: float = 0.0

## 入树前保存 [param battle] 的 [param cards]，用 [param random] 微调落点与卡片倾斜。
func configure(battle: RepeaterShotContext, cards: Array[Card], random: RandomNumberGenerator) -> void:
	_battle = battle
	_cards = cards
	for index: int in range(cards.size()): # 固定落点间隔，使用小抖动避免整齐横排。
		_landings.append(Vector2(LANES[index] + random.randf_range(-0.028, 0.028),
			DEPTHS[index] + random.randf_range(-0.045, 0.045)))
		_bank.append(TILTS[index] + random.randf_range(-0.06, 0.06))

## 建立无输入的 FX 层。每张卡落地才登记，飞行中不会误触。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_live = _cards.size()
	_fit_field()
	_avoid_older_cards()
	for card: Card in _cards: # 使用真实卡面展示升星、转职和零费。
		card.hide()
		add_child(card)
		card.pivot_offset = card.size * 0.5
		card.mouse_filter_stop()
		card.tree_exiting.connect(_on_card_departing, CONNECT_ONE_SHOT)
	EventBus.subscribe("main_game_progress_update", _on_progress_changed)
	TreePauseManager.pause_factors_changed.connect(_check_battle)
	get_viewport().size_changed.connect(_on_resize)
	var flight: Tween = create_tween().set_ignore_time_scale(true) # 与通用 Cut-in 同步，暂停时一并停止。
	flight.tween_method(_render_frame, 0.0, DURATION, DURATION)

## 切场离树时解除事件总线订阅；节点绑定的 Tween 随同释放。
func _exit_tree() -> void:
	EventBus.unsubscribe("main_game_progress_update", _on_progress_changed)

## 按当前可见棋盘计算安全区域，纸面留开卡槽、侧边和底部的交互位置。
func _fit_field() -> void:
	var view: Rect2 = get_viewport().get_visible_rect() # 所有几何使用同一个战斗 HUD 视口坐标。
	_fit = minf(view.size.x / 1066.0, view.size.y / 600.0)
	var safe := Rect2(view.position + view.size * Vector2(0.13, 0.18), view.size * Vector2(0.74, 0.69)) # 标题和牌库区保持可见。
	var board_area: Rect2 = _battle.game.get_canvas_transform() * BoardQueries.bounds(_battle.board.cells()) # 兼容屋顶、泳池及稀疏棋盘。
	_field = safe.intersection(board_area)
	if _field.size.x < safe.size.x * 0.62 or _field.size.y < safe.size.y * 0.62:
		_field = safe
	_origin = _field.position + _field.size * Vector2(0.50, 0.045)

## 尽量避开之前未使用的临时卡；保留每张卡的横向分区和本批的分散布局。
func _avoid_older_cards() -> void:
	var standing := PackedVector2Array() # 只在施放时采样，已落地的卡不会因新施放移动。
	for card: Card in _battle.game.card_manager.curr_temp_cards: # 包含种子雨或先前的邮差卡。
		if is_instance_valid(card) and not card.is_queued_for_deletion():
			standing.append(card.get_global_transform_with_canvas() * (card.size * 0.5))
	if standing.is_empty():
		return
	for index: int in range(_landings.size()): # 同列依次找离已有卡较远的位置。
		var best: Vector2 = _landings[index] # 距离并列时保留本批原先的深浅关系。
		var best_gap: float = -1.0 # 尚未评估任何候选。
		for delta: float in [0.0, 0.23, -0.23, 0.4, -0.4]: # 卡片只在各自纵区内换备选位置。
			var candidate := Vector2(best.x, clampf(_landings[index].y + delta, 0.20, 0.86))
			var point: Vector2 = _field.position + _field.size * candidate # 用屏幕像素比较各落点的距离。
			var gap: float = INF # 到最近临时卡的距离，用来挑疏处。
			for occupied: Vector2 in standing: # 当前已有卡不足以占满棋盘时优先保留首选位置。
				gap = minf(gap, occupied.distance_to(point))
			if gap > best_gap:
				best = candidate
				best_gap = gap
			if gap >= 85.0 * _fit:
				break
		_landings[index] = best
		standing.append(_field.position + _field.size * best)

## 视口变化时重投影相同的落点，已经发放的卡只更新位置与缩放。
func _on_resize() -> void:
	if _battle.is_active():
		_fit_field()
		_render_frame(_age)

## [param _progress] 表示战斗流程切换，立即清除原阶段未交付或未使用的卡片。
func _on_progress_changed(_progress: int) -> void:
	_check_battle()

## 检查阶段和战场所有权。普通菜单暂停继续保留卡片，续战前收回。
func _check_battle() -> void:
	if is_queued_for_deletion() or _battle.is_active():
		return
	var hand: HandManager = _battle.game.hand_manager if is_instance_valid(_battle.game) else null # 只放下本次派送的手持卡。
	if is_instance_valid(hand) and is_instance_valid(hand.hm_character.curr_card) and _cards.has(hand.hm_character.curr_card):
		hand.curr_hm_status = HandManager.E_HandManagerStatus.Null
	hide()
	queue_free()

## 最后一张真实卡消耗后释放派送控件及其绘制资源。
func _on_card_departing() -> void:
	_live -= 1
	if _live == 0 and not is_queued_for_deletion():
		queue_free()

## [param index] 的出发时刻，保持三张错峰入场。
func _launch_at(index: int) -> float:
	return LAUNCH + index * STAGGER

## [param index] 的触地时刻；三张卡的飞行长度略有差别。
func _land_at(index: int) -> float:
	return _launch_at(index) + FLIGHT + index * 0.045

## 将 [param index] 的归一化落点投影到当前可见棋盘。
func _landing(index: int) -> Vector2:
	return _field.position + _field.size * _landings[index]

## 返回 [param index] 的 [param t] 飞行进度处的抛物线位置，先弹起再落下。
func _flight_point(index: int, t: float) -> Vector2:
	var arc: float = minf(87.0 * _fit, _field.size.y * 0.26) # 保证小屏不把卡抬出视口。
	return _origin.lerp(_landing(index), t) - Vector2(0.0, 4.0 * t * (1.0 - t) * arc)

## [param elapsed] 同时推进实卡姿态和轻量纸带，在触地时接入原生临时卡。
func _render_frame(elapsed: float) -> void:
	if not _battle.is_active():
		_check_battle()
		return
	_age = elapsed
	for index: int in range(_cards.size()): # 逐张落地交付，先到的卡可先用。
		var card: Card = _cards[index] # 卡片落地后可以在其余动画完成前被玩家消耗。
		if not is_instance_valid(card) or card.is_queued_for_deletion() or elapsed < _launch_at(index):
			continue
		var t: float = clampf(inverse_lerp(_launch_at(index), _land_at(index), elapsed), 0.0, 1.0) # 真实飞行所处比例。
		var rebound: float = maxf(0.0, 1.0 - absf((elapsed - _land_at(index)) / 0.17 - 0.5) * 2.0) # 落地后只回弹数像素。
		var bump: float = sin(t * PI) # 旋转和展开在着地时自然归零。
		card.show()
		card.position = _flight_point(index, t) - card.size * 0.5 - Vector2(0.0, 6.0 * rebound * _fit)
		card.rotation = _bank[index] * bump
		card.scale = Vector2.ONE * _fit * (lerpf(0.63, 1.0, smoothstep(0.0, 0.48, t)) + 0.10 * bump)
		card.modulate.a = smoothstep(0.0, 0.16, t)
		if t == 1.0 and not _delivered.has(index):
			_delivered[index] = true
			card.card_context = Card.CardContext.Battle
			card.mouse_filter_start()
			_battle.game.card_manager.register_temp_card(card)
			var expiry: Control = ParcelExpiry.new() # 精确从本卡落地登记时开始十五秒。
			expiry.configure(card, _battle.game.card_manager)
			card.add_child(expiry)
			SoundManager.play_other_SFX(&"tap2")
	queue_redraw()

## 同一层绘制信封、卡片轨迹及触地纸屑；完成后不持续生成节点或更新画面。
func _draw() -> void:
	var seal: float = smoothstep(LAUNCH - 0.20, LAUNCH, _age) * (1.0 - smoothstep(LAUNCH + 0.29, LAUNCH + 0.53, _age)) # 信封只在实际投递期间透出。
	if seal > 0.0:
		_draw_envelope(seal)
	for index: int in range(_cards.size()): # 三路短尾和落地章都由单个控件绘制。
		var t: float = inverse_lerp(_launch_at(index), _land_at(index), _age) # 负值尚未出场。
		if t > 0.0 and t < 1.0:
			_draw_ribbon(index, t)
		var ground_age: float = _age - _land_at(index) # 印记随各自触地时间淡出。
		if ground_age >= 0.0 and ground_age < 0.42:
			_draw_stamp(_landing(index), ground_age / 0.42)

## 按 [param opacity] 绘制松开封口的信封，纸白与雨蓝呼应角色立绘。
func _draw_envelope(opacity: float) -> void:
	var corners := PackedVector2Array([Vector2(-26, -9), Vector2(25, -12), Vector2(27, 11), Vector2(-24, 14)]) # 略俯视的信封外轮廓。
	var lid := PackedVector2Array([Vector2(-26, -9), Vector2(-1, -26), Vector2(25, -12)]) # 掀起的封舌给三张卡让出出发口。
	draw_set_transform(_origin, -0.08, Vector2.ONE * _fit)
	draw_circle(Vector2.ZERO, 35.0, Color(BLUE, opacity * 0.17), true, -1.0, true)
	draw_colored_polygon(lid, Color("b1c7df", opacity))
	draw_colored_polygon(corners, Color(PAPER, opacity))
	corners.append(corners[0])
	draw_polyline(corners, Color(INK, opacity * 0.95), 1.7, true)
	draw_polyline(PackedVector2Array([corners[0], Vector2(0, 5), corners[1]]), Color(INK, opacity * 0.60), 1.3, true)
	draw_circle(Vector2(0.0, 5.0), 3.6, Color("dd7b79", opacity), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)

## 描绘 [param index] 在 [param t] 处的弯曲短尾，末端不在场上留下整条路径。
func _draw_ribbon(index: int, t: float) -> void:
	var tail := PackedVector2Array() # 八点即可给短弧足够圆滑的轮廓。
	for segment: int in range(8): # 从较暗尾端采样到正在飞行的卡面正下方。
		tail.append(_flight_point(index, lerpf(maxf(0.0, t - 0.30), t, segment / 7.0)))
	var alpha: float = sin(t * PI) # 飞到两端时同步收束线条。
	draw_polyline(tail, Color(BLUE, alpha * 0.25), 12.0 * _fit, true)
	draw_polyline(tail, Color(PAPER, alpha * 0.78), 2.3 * _fit, true)

## 在 [param center] 显示归一化年龄 [param t] 的轻弹印记及少量纸片。
func _draw_stamp(center: Vector2, t: float) -> void:
	var reveal: float = 1.0 - smoothstep(0.12, 1.0, t) # 印记比卡片回弹稍晚退去。
	var radius: float = lerpf(14.0, 53.0, 1.0 - pow(1.0 - t, 2.0)) * _fit # 心部先亮，外围展开。
	draw_set_transform(center + Vector2(0, 22) * _fit, 0.0, Vector2(1.0, 0.48))
	draw_arc(Vector2.ZERO, radius, 0.1, 6.11, 30, Color(BLUE, reveal * 0.82), 2.3 * _fit, true)
	draw_arc(Vector2.ZERO, radius * 0.78, 0.65, 4.97, 24, Color(PAPER, reveal * 0.63), 1.6 * _fit, true)
	draw_set_transform(Vector2.ZERO)
	for index: int in range(7): # 只在每次触地发出七片宽度各异的微小纸屑。
		var direction: Vector2 = Vector2.from_angle(index * 2.39996) # 互质角步长，不聚成规则圆点。
		var piece: Vector2 = center + direction * radius * (0.65 + index % 3 * 0.16) - Vector2(0, 21 * sin(t * PI)) * _fit # 纸屑当前的屏幕坐标。
		var stretch: Vector2 = direction * (2.7 + index % 3) * _fit # 薄纸沿飞散方向拉长。
		draw_line(piece - stretch, piece + stretch, Color(PAPER if index % 2 == 0 else BLUE, reveal * 0.85), 2.1 * _fit, true)
