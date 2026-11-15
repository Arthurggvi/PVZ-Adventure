## 回旋镖射手；自然发射、有限连发和真实回收补投互不占用对方的机械状态。
extends Plant000Base
class_name Plant051Bloomerang

## 按出战星级冻结投掷和命中音色。
const Audio = preload("res://scripts/character/plant/bloomerang_audio.gd")
## 幂等保存本株已选转职事件，不修改原始卡片或其他植物。
var _rules: Dictionary = {}
## 唯一自然攻击时钟，动画中断和接镖均不能把它锁死。
var _cycle: BloomerangAttackCycle = BloomerangAttackCycle.new()
## 本次自然事务的冻结战斗身份及伤害配置；结束或取消时释放。
var _shot: BloomerangShotContext
## 本次事务需要发射的独立方向，扫荡时前后各一枚。
var _directions: Array[int] = []
## 实际出战关卡，固定到出生实例，不借用后来的其他场景。
var _game: MainGameManager
## 当前自然攻击允许使用的轮次；换轮先取消旧事务。
var _round_index: int = -1
## 通用角色速度因素乘积，冻结和眩晕为零；不含本株独立转职攻速。
var _owner_speed: float = 1.0
## 岚刀只加速本株攻击时钟及攻击表现，不改待机、接镖和其他组件。
var _attack_multiplier: float = 1.0
## 仅登记尚未回收或离树的真实弹 ID，回收先移除，避免重入重复补投。
var _in_flight: Dictionary[int, bool] = {}
## 同行索敌及子弹可攻击状态的共同来源。
@onready var _detect: DetectComponent = $DetectComponent
## 动画仅负责表现，不再通过方法轨发弹或维持攻击锁。
@onready var _animation: AnimationPlayer = $AnimationPlayer
## 母株当前的离手点与真实接镖位置，随平台移动。
@onready var _launch: Marker2D = $Body/BodyCorrect/Launch
## 已冻结的声音档，派生投射物继续沿用。
@onready var _sound_tier: int = Audio.tier_for(plant_spawn_profile)

## [param events] 为已验证的完整转职事件；重复配置不叠加倍率或连接信号。
func configure_promotions(events: Array[Dictionary]) -> void:
	var next_rules: Dictionary = {} # 只保留本物种的事件副本，避免外部修改正在进行的事务。
	for event: Dictionary in events: # 事件种类由目录和调度器统一验证。
		var kind: String = str(event.get("kind", "")) # 以稳定事件键作为幂等身份。
		if kind.begins_with("bloomerang_"):
			next_rules[kind] = event.duplicate(true)
	if next_rules == _rules:
		return
	_cancel_attack()
	_rules = next_rules
	var blade: Dictionary = _rules.get("bloomerang_storm_blade", {}) # 没选岚刀时保持原速度。
	_attack_multiplier = 1.0 + maxf(0.0, float(blade.get("attack_rate_bonus", 0.7))) \
		if _rules.has("bloomerang_storm_blade") else 1.0

## 入树即订阅阶段边界；同帧合法重挂时也会重新订阅，不能跨轮保留旧连发。
func _enter_tree() -> void:
	if character_init_type == E_CharacterInitType.IsNorm:
		EventBus.subscribe("main_game_progress_update", _on_progress_changed)

## 正常出战才建立机械状态；展示和花园仍只播放原待机动作。
func _ready() -> void:
	super()
	_animation.animation_finished.connect(_on_animation_finished)
	set_physics_process(character_init_type == E_CharacterInitType.IsNorm)
	if character_init_type != E_CharacterInitType.IsNorm:
		return
	_game = Global.main_game
	_round_index = _game.curr_game_round if is_instance_valid(_game) else -1
	_owner_speed = GlobalUtils.get_dic_product(influence_speed_factors)
	signal_update_speed.connect(_on_owner_speed_changed)
	signal_character_death.connect(_cancel_attack)
	sleep_component.signal_is_sleep.connect(_cancel_attack)

## [param delta] 已包含引擎时间倍率；独立攻速只乘一次，有限事务不追赶历史攻击。
func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	if is_instance_valid(_game) and _game.curr_game_round != _round_index:
		_cancel_attack()
		_round_index = _game.curr_game_round
	if not _can_emit():
		_cancel_attack()
		return
	var edges: Vector2 = BloomerangEmitter.battle_edges(self) # 本帧真实视野，平台移动时不沿用旧中心。
	BloomerangEmitter.update_detection(_detect, edges)
	var step: Dictionary = _cycle.advance(delta * _owner_speed * _attack_multiplier) # 所有自然动作只消费这一个时钟。
	if bool(step.sound):
		Audio.play_throw(_sound_tier)
	for _wave: int in range(int(step.waves)): # 单帧至多三轮，每个方向都重新检查发射资格。
		if _shot == null or not _can_emit():
			_cancel_attack()
			break
		var transaction: BloomerangShotContext = _shot # 入树信号可取消本株，双向续发必须仍属于这一事务。
		for launch_direction: int in _directions.duplicate(): # 不遍历可能被同步取消清空的原方向表。
			if _shot != transaction or not _can_emit():
				break
			_emit_shot(transaction.for_direction(launch_direction))
	if bool(step.finished):
		_shot = null
		_directions.clear()
		if _animation.current_animation in [&"", &"attack"]:
			_animation.play(&"idle")
	if _cycle.can_begin():
		if BloomerangEmitter.has_target(self, _detect, _rules.has("bloomerang_sweep"), edges):
			_begin_attack()
		else:
			_cycle.retry_target()

## 起手时只投一次风切概率，冻结本次方向和伤害上下文。
func _begin_attack() -> void:
	if not _can_emit() or not _cycle.can_begin():
		return
	var wind: Dictionary = _rules.get("bloomerang_wind_cut", {}) # 无词条时不消耗三连发随机数。
	var shots: int = 1 # 额外回收补投不会进入此入口。
	if _rules.has("bloomerang_wind_cut") and randf() < clampf(float(wind.get("chance", 0.5)), 0.0, 1.0):
		shots = clampi(int(wind.get("shots", 3)), 1, BloomerangAttackCycle.MAX_SHOTS)
	_shot = BloomerangShotContext.from_plant(self, _rules, 1)
	if _shot == null:
		_cycle.retry_target()
		return
	_shot.attack_context = capture_attack_context()
	_directions.assign([1, -1] if _rules.has("bloomerang_sweep") else [1])
	_cycle.begin(shots)
	_animation.play(&"attack", -1.0, _attack_multiplier)

## [param shot] 是此次单枚离手的独立快照；返回是否真实生成，不改变自然冷却。
func _emit_shot(shot: BloomerangShotContext) -> bool:
	if not _can_emit() or shot == null or not shot.is_active() \
			or shot.source_id != get_instance_id():
		return false
	var bullet: Bullet017Boomerang = BloomerangEmitter.create(self, _launch, _detect, shot, _sound_tier) # 先配置，再登记，最后入树。
	if bullet == null:
		return false
	var projectile_id: int = bullet.get_instance_id() # 一枚真实弹对应一个可消费的回收身份。
	_in_flight[projectile_id] = true
	bullet.returned.connect(_on_boomerang_returned, CONNECT_ONE_SHOT)
	bullet.tree_exiting.connect(_forget_projectile.bind(projectile_id), CONNECT_ONE_SHOT)
	shot.game.bullets.add_child(bullet)
	return true

## [param projectile_id] 必须属于本株尚未消费的真实弹；[param shot] 保留原出手战场及方向。
## 先消费身份再补投，补投不投风切概率、不重置冷却，也不能再次触发螺旋。
func _on_boomerang_returned(projectile_id: int, shot: BloomerangShotContext) -> void:
	if not _in_flight.has(projectile_id):
		return
	_in_flight.erase(projectile_id)
	if not _can_emit() or shot == null or not shot.is_active() or shot.source_id != get_instance_id():
		return
	if shot.allow_echo and not shot.is_split and _emit_shot(shot.for_echo()):
		Audio.play_throw(_sound_tier)
	if not _cycle.is_busy() and _animation.current_animation != &"catch":
		_animation.play(&"catch")

## [param projectile_id] 对应的弹无论回收、出屏或被清场，都应移除登记，避免长期增长。
func _forget_projectile(projectile_id: int) -> void:
	_in_flight.erase(projectile_id)

## 唯一发射门禁，外部 returned 直接调用同样不能绕过无效化或暂停。
func _can_emit() -> bool:
	return BloomerangEmitter.can_emit(self, _game, _round_index, _owner_speed)

## 取消未发出的自然轮次；已经离手的弹继续按自己的冻结战场处理。
func _cancel_attack() -> void:
	_cycle.cancel()
	_shot = null
	_directions.clear()
	if is_instance_valid(_animation) and is_inside_tree() and not is_death \
			and _animation.current_animation == &"attack":
		_animation.play(&"idle")

## [param progress] 的任何正式战斗外阶段都清除旧事务，即使母株正被禁用。
func _on_progress_changed(progress: int) -> void:
	if progress != MainGameManager.E_MainGameProgress.MAIN_GAME or _game != Global.main_game:
		_cancel_attack()

## [param speed_product] 为通用角色动作倍率；零速取消未离手动作，恢复时不补发旧连发。
func _on_owner_speed_changed(speed_product: float) -> void:
	_owner_speed = maxf(0.0, speed_product) if is_finite(speed_product) else 0.0
	if _owner_speed <= 0.0:
		_cancel_attack()

## [param what] 的禁用通知也会在停止物理帧前到达，避免无效化结束后恢复旧起手。
func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED:
		_cancel_attack()

## [param animation_name] 仅用于恢复表现；不能清除、开启或锁住机械攻击事务。
func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name in [&"attack", &"catch"] and not _cycle.is_busy() \
			and not is_death and _animation.current_animation in [&"", animation_name]:
		_animation.play(&"idle")

## 离场取消旧动作；手套换格保留同一战场中的攻击与冷却进度。
func _exit_tree() -> void:
	if not is_being_relocated:
		_cancel_attack()
	EventBus.unsubscribe("main_game_progress_update", _on_progress_changed)
