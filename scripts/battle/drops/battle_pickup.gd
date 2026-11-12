## 战场掉落物基类：抛物线抛出、落地音效、超时淡出、点击/磁力收集与飞向 UI 的动画。
## 子类只需覆盖 [_grant] 决定拾取后入账什么，掉落表现与音效由本类统一处理。
extends Node2D
class_name BattlePickup

## 成功收集并入账后发出，供掉落统计、额度控制等外部逻辑使用。
signal collected(pickup: BattlePickup)

## 抛出瞬间播放的音效键；留空时抛出无声。
@export var launch_sound: StringName = &""
## 首次落地时播放的音效键；留空时落地无声。
@export var landing_sound: StringName = &""
## 开始收集时播放的音效键；留空时收集无声。
@export var pickup_sound: StringName = &"coin"
## 未被拾取时的存在时间（秒）；小于等于零时常驻战场。
@export var exist_time: float = 10.0
## 抛出到落地的飞行时间（秒）。
@export var duration: float = 0.55
## 抛物线相对起止连线的最大抬升高度（正值）。
@export var peak_height: float = 70.0

@onready var anim_lib: AnimationPlayer = get_node_or_null("AnimLib") as AnimationPlayer
@onready var button: TextureButton = get_node_or_null("Button") as TextureButton

## 收集飞行的目标锚点（如金币栏），可与掉落物处于不同画布。
var target: Node2D
## 超时淡出的补间；收集开始时终止，避免在入账前移除。
var _expiry_tween: Tween
## 抛出抛物线补间。
var tween: Tween
## 是否已被收集。
var is_get := false
## 是否允许自动拾取装备在落地时收取本掉落物。
var auto_collect_on_landing := true
## 入账是否已处理；奖杯可接管正在飞行的掉落物，但只能入账一次。
var _grant_attempted := false
## 生成时绑定的档案；飞行动画结束不能向新玩家入账。
var _owner_state: AdventureState
## 生成时所属战斗节点，花园等非战斗拾取不绑定。
var _source_game: MainGameManager
## 是否需要验证原战斗仍为当前战斗。
var _battle_bound: bool = false

## 是否可以播放待机动画；没有 AnimLib 的掉落物保持静止。
@export var is_anim := false:
	set(value):
		is_anim = value
		if anim_lib == null:
			return
		if value:
			anim_lib.play("ALL_ANIMS")
		else:
			anim_lib.seek(0.0, true)
			anim_lib.stop(true)

## 设置 [param new_target] 为本次掉落的收集锚点。
func setup(new_target: Node2D) -> void:
	target = new_target

func _ready() -> void:
	_owner_state = Global.global_game_state.adventure_state
	if is_instance_valid(Global.main_game) and Global.main_game.is_ancestor_of(self):
		_source_game = Global.main_game
		_battle_bound = true
	if button != null:
		button.pressed.connect(collect)
		if is_instance_valid(Global.main_game) and Global.main_game.game_para.is_hammer:
			button.mouse_entered.connect(Global.main_game.mouse_appear_have_hammer)
			button.mouse_exited.connect(Global.main_game.mouse_disappear_have_hammer)
	if exist_time > 0.0:
		await get_tree().create_timer(exist_time, false).timeout
		fade_and_delete()

## 仅未收集的掉落物超时淡出，收集中的由收集流程清理。
func fade_and_delete() -> void:
	if is_get:
		return
	_expiry_tween = create_tween()
	_expiry_tween.tween_property(self, "modulate:a", 0.0, 1.0)
	_expiry_tween.tween_callback(queue_free)

## 以 [param relative_target] 为抛物落点抛出，落地后检查装备是否允许自动收集。
func launch(relative_target: Vector2) -> void:
	is_anim = false
	if not launch_sound.is_empty():
		SoundManager.play_other_SFX(launch_sound)
	var start_pos: Vector2 = position
	var end_pos: Vector2 = start_pos + relative_target

	tween = create_tween()
	tween.set_parallel()
	# 水平 x：线性插值
	tween.tween_property(self, "position:x", end_pos.x, duration)
	# 垂直 y：使用函数插值构建抛物线
	tween.tween_method(
		func(t):
			# t ∈ [0, 1]，计算当前 y
			var y = lerp(start_pos.y, end_pos.y, t) - 4 * peak_height * t * (1 - t)
			position.y = y,
		0.0,
		1.0,
		duration
	).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)

	await tween.finished
	tween = null
	is_anim = true
	if not landing_sound.is_empty():
		SoundManager.play_other_SFX(landing_sound)
	if auto_collect_on_landing and BattleCollectionPolicy.allows(false):
		collect()

## 外部中断抛出动画（如场景切换）。
func _on_interrupt_triggered() -> void:
	if tween:
		tween.kill()
		tween = null

## 为本次收集占用掉落物；[param play_sound] 控制拾取音效，重复请求返回 false。
func _begin_collection(play_sound: bool = true) -> bool:
	if is_get or is_queued_for_deletion():
		return false
	is_get = true
	if _expiry_tween != null:
		_expiry_tween.kill()
		modulate.a = 1.0
	if play_sound and not pickup_sound.is_empty():
		SoundManager.play_other_SFX(pickup_sound)
	_on_interrupt_triggered()
	_on_collect_start()
	return true

## 飞向锚点后入账；[param flight_time] 是飞行秒数，[param play_sound] 控制拾取音效。
func collect(flight_time: float = 0.5, play_sound: bool = true) -> void:
	if not _begin_collection(play_sound):
		return
	if button != null:
		button.queue_free()
	is_anim = false

	var start_position: Vector2 = global_position # 起点使用掉落物自己的世界坐标。
	var click_tween: Tween = create_tween() # 收集飞行动画。
	click_tween.tween_method(func(weight: float) -> void: # 插值权重从起点的 0 过渡到终点的 1。
		if is_instance_valid(target):
			var screen_target: Vector2 = target.get_global_transform_with_canvas().origin # 每帧读取锚点的视口坐标。
			global_position = start_position.lerp(get_canvas_transform().affine_inverse() * screen_target, weight)
	, 0.0, 1.0, flight_time)
	await click_tween.finished
	_finish_grant()
	click_tween = create_tween()
	click_tween.set_parallel()
	click_tween.tween_property(self, "modulate:a", 0, 0.5)
	click_tween.tween_property(self, "scale", Vector2(0.5, 0.5), 0.5)

	await click_tween.finished
	queue_free()

## 奖杯整批收取时立即入账并清除实体，包含此前已经开始飞行的掉落物。
func collect_now() -> void:
	if is_queued_for_deletion():
		return
	if not is_get:
		_begin_collection(false)
	_finish_grant()
	hide()
	queue_free()

## 吸金磁收集时飞向 [param target_global_pos]，到达后入账。
func be_attract_gold_magnet(target_global_pos: Vector2) -> void:
	if not _begin_collection():
		return

	var attract_tween: Tween = create_tween()
	attract_tween.tween_property(self, "global_position", target_global_pos, 0.5)
	await attract_tween.finished
	_finish_grant()
	attract_tween = create_tween()
	attract_tween.set_parallel()
	attract_tween.tween_property(self, "modulate:a", 0, 0.5)
	attract_tween.tween_property(self, "scale", Vector2(0.5, 0.5), 0.5)

	await attract_tween.finished
	queue_free()

## 仅在首次入账尝试成功时发出收集信号。
func _finish_grant() -> void:
	if _grant_attempted:
		return
	_grant_attempted = true
	if _can_grant() and _grant():
		collected.emit(self)

## 验证生成时的档案与场景身份；过期的异步动画不能修改当前玩家。
func _can_grant() -> bool:
	return _owner_state == Global.global_game_state.adventure_state \
		and (not _battle_bound or (is_instance_valid(_source_game) and Global.main_game == _source_game))

## 拾取入账；由子类返回是否真正成功，失败不能计入拾取额度。
func _grant() -> bool:
	return false

## 收集开始时的额外表现（子类可覆盖，如停止待机动画）。
func _on_collect_start() -> void:
	pass
