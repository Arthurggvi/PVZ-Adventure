## 明灯的战斗入口。按行为树释放技能，转阶段与死亡可抢占普通行动。
extends ZB000Base
class_name ZB004MingLantern

## 真实出战与图鉴复用同一场表现。
@onready var presentation: MingLanternPresentation = $Body/MingLanternPresentation
## 每个实战实例独立计时和抽取技能。
var _behavior := MingLanternBehaviorTree.new()
## 二阶段本轮的第二个普通技能，当前技能结束后释放。
var _next_skill: StringName = &""
## 当前战场的落点和推移结算。
var _combat: MingLanternCombat
## 存档只还原血量和形态，不重放已发生过的登场攻击。
var _restored := false
## 首次完整入场后开放 Boss 曲，之后的滔天退回场不重置。
var _entrance_complete := false

## 首次入场结束或读档直接归位后，才允许战场播放 Boss 曲。
func is_boss_music_ready() -> bool:
	return _entrance_complete or _restored

## [param manager] 提供棋盘，[param _spawn_lane] 是共用工厂参数；明灯从整片棋盘的右缘露面。
func get_default_boss_spawn_position(manager: ZombieManager, _spawn_lane: int = -1) -> Vector2:
	var bounds: Rect2 = BoardQueries.bounds(manager.main_game.board.cells()) # 保证三个演出形态以可种区域右侧为准。
	if not bounds.has_area():
		return super.get_default_boss_spawn_position(manager, _spawn_lane)
	return manager.zombie_boss_root.to_local(Vector2(bounds.end.x + 54.0, bounds.get_center().y - 18.0))

## 初始化受击窗口，延后到管理器提交棋盘与血量后播放开场。
func ready_norm() -> void:
	super.ready_norm()
	set_physics_process(false)
	presentation.visual.hide()
	presentation.action_finished.connect(_on_action_finished)
	signal_action_rate_changed.connect(presentation.set_action_rate)
	_set_invulnerable(true)
	_begin_battle.call_deferred()

## 关卡角色预览只展示待机。
func ready_show() -> void:
	super.ready_show()
	presentation.visual.set_phase(1)
	set_physics_process(false)

## [param remaining_hp] 为保存的当前生命。形态静默同步，开场攻击不会重播。
func restore_boss_hp(remaining_hp: int) -> void:
	_restored = true
	super.restore_boss_hp(remaining_hp)

## [param ratio] 是遭遇初始生命比例，[param retreat]、[param summon_tier] 为通用遭遇参数。
## 指定初始血量仍属于新登场，应播放开场。
func configure_adventure_encounter(ratio: float, retreat: bool, summon_tier: StringName) -> void:
	if ratio == phase_two_threshold_ratio:
		# 基类的预设半血后备分支包含等号，明灯必须严格低于半血。
		super.configure_adventure_encounter(1.0, retreat, summon_tier)
		super.restore_boss_hp(floori(hp_component.max_hp * ratio))
	else:
		super.configure_adventure_encounter(ratio, retreat, summon_tier)
	_restored = false

## 查找真正容纳本体的战场，绑定实际棋盘再开启时间轴。
func _begin_battle() -> void:
	var ancestor: Node = get_parent() # Boss 位于管理器分配的战场容器下。
	while ancestor != null and not ancestor is MainGameManager:
		ancestor = ancestor.get_parent()
	if ancestor == null or is_death:
		return
	_combat = MingLanternCombat.new()
	_combat.game = ancestor as MainGameManager
	_combat.caster = self
	if not _combat.active():
		return
	presentation.configure(_combat.game.board, _combat)
	presentation.reset(boss_phase)
	set_physics_process(true)
	if _restored:
		_set_invulnerable(false)
	else:
		presentation.play_action(&"entrance")

## [param delta] 为战斗秒数。普通技能耗时计入八秒间隔，忙碌时等本轮播完再启动下一轮。
func _physics_process(delta: float) -> void:
	if not _battle_active():
		return
	var skills: Array[StringName] = _behavior.tick(delta * action_rate(), presentation.is_busy(), boss_phase >= 2) # 过半后普通一轮含两个技能。
	if not skills.is_empty() and perform_action(skills[0]) and skills.size() > 1:
		_next_skill = skills[1]

## 仍存活并属于正在运行的原战场时返回 true。
func _battle_active() -> bool:
	return not is_death and not is_queued_for_deletion() and _combat != null \
		and _combat.active() and _combat.game.is_ancestor_of(self)

## 执行一轮的首个技能 [param action]，可供战斗时钟或外部明确调用。忙碌、无效技能或战斗结束时返回 false。
func perform_action(action: StringName) -> bool:
	if not _battle_active() or presentation.is_busy():
		return false
	if action == &"tidal":
		_start_tidal(false)
		return true
	if not MingLanternBehaviorTree.REGULAR_SKILLS.has(action) or not presentation.play_action(action):
		return false
	_behavior.start_turn(action)
	return true

## 开启滔天并清除本轮未释放的技能。[param transform_on_return] 使强化效果立即生效，回场时才切换外观。
func _start_tidal(transform_on_return: bool) -> void:
	_next_skill = &""
	_behavior.start_turn(&"tidal")
	_set_invulnerable(true)
	presentation.play_action(&"tidal", transform_on_return)

## [param phase] 到达二阶段时强化滔天；[param animated] 为 false 时直接恢复存档形态。
func _apply_boss_visual_phase(phase: int, animated: bool) -> void:
	# 明灯使用独立的呼吸光，与基类默认整身变暗分开。
	body.set_boss_phase_pulse(false)
	if animated and _battle_active():
		_start_tidal(true)
	else:
		presentation.visual.set_phase(phase)

## [param enabled] 控制入场和滔天的受击窗口，同时刷新植物的目标资格。
func _set_invulnerable(enabled: bool) -> void:
	hp_component.damage_immune = enabled
	hurt_box_component.change_is_enabling(not enabled, ComponentNormBase.E_IsEnableFactor.Character)
	signal_status_update.emit()

## [param action] 结束后接续本轮第二个技能、恢复受击或在退场结束时走共用奖杯入口。
func _on_action_finished(action: StringName) -> void:
	if action == &"death":
		request_trophy()
		queue_free()
		return
	if not _battle_active():
		return
	if action in [&"entrance", &"tidal"]:
		if retreat_after_phase_two and boss_phase == 2 and action == &"tidal":
			queue_free()
		else:
			_behavior.restart_wait()
			_set_invulnerable(false)
			if action == &"entrance":
				_entrance_complete = true
				_combat.game.refresh_battle_bgm()
	elif not _next_skill.is_empty():
		var next: StringName = _next_skill # 第二个技能和首个技能同属一轮，不另计冷却或滔天次数。
		_next_skill = &""
		presentation.play_action(next)

## 死亡时清空场上僵尸，并播放短震和退场。先发出死亡信号，让遭遇停止生成援军。
func character_death() -> void:
	if is_death:
		return
	super.character_death()
	_next_skill = &""
	set_physics_process(false)
	presentation.play_action(&"death")
	if _combat != null:
		_combat.defeat_remaining_zombies()
