## 大喷菇单株攻击接入；原生射击与海神脉冲共用检测、伤害上下文和命中词条。
extends Node
class_name AdventureFumePromotionEffects
## 海神伤害使用固定战斗秒，正向射速加成不能缩短该周期。
const PULSE_SECONDS: float = 0.5
## 全行几何的兜底更新周期，射击或脉冲前还会即时更新。
const RANGE_REFRESH_SECONDS: float = 0.2
## 入树前配置的真实大喷菇。
var _plant: Plant011FumeShroom
## 当前实际战场，续战保留实体时每次攻击重新捕获阶段。
var _game: MainGameManager
## 原生攻击组件持有唯一伤害时钟。
var _attack: AttackComponentBulletBase
## 本株已选的冻结转职事件。
var _rules: Dictionary = {}
## 仅全行路线拥有范围辅助，不改其他实例的共享资源。
var _range: AdventureFumeRange
## 本轮原生发射的快照，所有弹口沿用一次抽签结果。
var _shot: AdventureFumeHitEffects
## 原生弹体定义中的基础伤害，读取一次而不另设大喷菇攻值。
var _base_damage: int = 0
## 全行几何下一次兜底更新前的剩余战斗秒。
var _range_left: float = RANGE_REFRESH_SECONDS
## 合并同帧重挂通知，真正离场才归还原生接口。
var _cleanup_pending: bool = false
## 全行矩形等待原生物理重叠缓存更新时，只保留一次已冻结的脉冲。
var _pulse_pending: bool = false
## 保存 [param plant] 和已验证的 [param events]，实际组件绑定等待父节点ready。
func configure(plant: Plant011FumeShroom, events: Array[Dictionary]) -> void:
	_plant = plant
	for event: Dictionary in events: # 只冻结本物种事件，不读取运行时可变背包。
		var kind: String = str(event.get("kind", "")) # 目录中的稳定事件标识。
		if kind.begins_with("fume_"):
			_rules[kind] = event.duplicate(true)

## 源被无效化后本监控仍可关闭喷雾，攻击时钟仍继承植物禁用与战场暂停。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if not is_instance_valid(_plant):
		queue_free()
	elif _plant.is_node_ready():
		_bind()
	else:
		_plant.ready.connect(_bind, CONNECT_ONE_SHOT)

## 绑定唯一原生发射入口，海神只切换攻击组件的执行方式，不再创建另一套计时器。
func _bind() -> void:
	_game = Global.main_game
	_attack = _plant.attack_component
	if not is_instance_valid(_game) or not is_instance_valid(_attack):
		return
	_attack.signal_shoot_bullet.connect(_on_native_shot)
	_attack.signal_bullet_instantiated.connect(_on_bullet_created)
	_plant.signal_character_death.connect(_stop_visuals, CONNECT_ONE_SHOT)
	if _rules.has("fume_full_row"):
		_range = AdventureFumeRange.new()
		_range.configure(_plant)
	if _rules.has("fume_poseidon"):
		var sample: Bullet000NormBase = Global.bullet_registry.get_bullet_scenes(_attack.attack_bullet_type).instantiate() as Bullet000NormBase # 只读取原生资源攻值，不将样本入树或发射。
		if sample == null:
			push_error("海神需要原生大喷菇弹体定义")
			return
		_base_damage = sample.attack_value
		sample.free()
		_plant.set_continuous_fume(true)
		_attack.configure_continuous_attack(PULSE_SECONDS, _pulse)
	set_process(_range != null or _rules.has("fume_poseidon"))

## [param delta] 是受战场暂停控制的秒数；每帧只同步视觉，伤害仅由固定脉冲触发。
func _process(delta: float) -> void:
	if _rules.has("fume_poseidon") and is_instance_valid(_plant):
		_plant.set_continuous_fume(true, _can_act())
	if _range != null:
		_range_left -= delta
		if _range_left <= 0.0:
			_range_left = RANGE_REFRESH_SECONDS
			if MushroomPlantQuery.is_active(_plant, _game):
				_range.refresh()

## 只允许真实在场、未禁用且非零速的大喷菇在当前正式战斗发起新攻击。
func _can_act() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() \
		and MushroomPlantQuery.is_active(_plant, _game) and is_instance_valid(_attack) \
		and _attack.is_enabling and _attack.is_attack_res \
		and GlobalUtils.get_dic_product(_plant.influence_speed_factors) > 0.0 \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME and not _game.get_tree().paused \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## 一次原生射击只捕获一次规则，犹格的随机结果由同一快照共享到本次全部目标。
func _on_native_shot() -> void:
	if _range != null:
		_range.refresh()
	_shot = AdventureFumeHitEffects.capture(_plant, _rules) if _can_act() else null

## [param created] 是尚未初始化的原生弹体；只添加范围、单目标去重和冻结命中回调。
func _on_bullet_created(created: Bullet000Base) -> void:
	var bullet: Bullet000NormBase = created as Bullet000NormBase # 保留注册表的原生大喷菇穿透弹。
	if bullet == null:
		return
	bullet.unique_target_hits = true
	bullet.attack_validity = _shot.is_active if _shot != null else AdventureFumePromotionEffects._reject_attack
	if _shot != null:
		bullet.impact_resolved.connect(_shot.apply)
	if _range != null and not _attack.markers_2d_bullet.is_empty():
		bullet.max_distance = _range.projectile_reach(
			_attack.markers_2d_bullet[0].global_position, bullet.max_distance)

## 无效来源的迟到动画仍可能进入原生发射；对应弹体在主伤害前直接被统一门禁拒绝。
static func _reject_attack() -> bool:
	return false
## 海神每半秒结算一次；无敌人时仅维持原生喷雾，不制造空弹体。
func _pulse() -> void:
	if _pulse_pending or not _can_act():
		return
	if _range != null:
		_range.refresh()
	var effects: AdventureFumeHitEffects = AdventureFumeHitEffects.capture(_plant, _rules) # 每次脉冲独立去重，上一脉冲不阻止后续命中。
	if effects == null or not effects.is_active():
		return
	var context: PlantAttackContext = _plant.capture_attack_context() # 同次脉冲的共享近伤、防具倍率等来源快照。
	var damage: int = _plant.battle_damage(_base_damage) # 原生基础攻值仅应用一次出战与来源伤害修饰。
	if _range != null:
		_pulse_pending = true
		get_tree().physics_frame.connect(_resolve_pulse.bind(effects, context, damage, true), CONNECT_ONE_SHOT)
	else:
		_resolve_pulse(effects, context, damage)

## [param effects]、[param context] 与 [param damage] 是本次时钟冻结的攻击；[param wait_step] 再等完整物理步。
## 延后只让原生Area2D缓存看到新矩形；不另建索敌，节点释放会自动断开单次回调。
func _resolve_pulse(effects: AdventureFumeHitEffects, context: PlantAttackContext, damage: int, wait_step: bool = false) -> void:
	if not _can_act() or not effects.is_active():
		_pulse_pending = false
		return
	if wait_step:
		get_tree().physics_frame.connect(_resolve_pulse.bind(effects, context, damage), CONNECT_ONE_SHOT)
		return
	_pulse_pending = false
	for target: Character000Base in _attack.detect_component.get_all_enemy_can_be_attacked(): # 复用原生范围、行、状态过滤与实例去重。
		if not effects.is_active() or (context != null and not context.is_active()):
			break
		if not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion() \
				or target.is_hypno or not is_instance_valid(target.hurt_box_component) \
				or not target.hurt_box_component.is_enabling:
			continue
		var position: Vector2 = target.hurt_box_component.global_position # 扣血可能使目标离场，提前保存实际命中点。
		var amount: int = context.modify_damage(damage, target) if context != null else damage # 每个目标独立按距离修饰。
		var casualty: Character000Base = null # 真实死者可为承受保护转伤的僵尸。
		if target is Zombie000Base:
			casualty = (target.hp_component as HpComponentZombie).apply_hit(
				amount, BulletRegistry.AttackMode.Penetration, true, true, true,
				context.armor_multiplier if context != null else 1.0)
			if is_instance_valid(target) and is_instance_valid(target.body):
				target.body.body_light()
		else:
			target.be_attacked_bullet(amount, BulletRegistry.AttackMode.Penetration)
			if is_instance_valid(target) and target is ZB000Base and target.is_death:
				casualty = target
		if context != null:
			context.resolve_kill(casualty) # 未致死也消费本次同步结算资格。
		effects.apply(target if is_instance_valid(target) else null, position)

## 死亡时立即停止产生新喷雾，已发射的快照仍由弹体自己持有。
func _stop_visuals() -> void:
	if is_instance_valid(_plant) and _rules.has("fume_poseidon"):
		_plant.set_continuous_fume(true, false)

## 真正释放后也可用弱引用归还组件接口；同帧正常回树时保持持续攻击模式。
func _exit_tree() -> void:
	if _cleanup_pending or not is_instance_valid(_attack):
		return
	_cleanup_pending = true
	AdventureFumePromotionEffects._finish_exit.call_deferred(
		weakref(self), weakref(_plant), weakref(_attack), _range, _pulse)

## 恢复监控不再configure攻击时钟，避免重复启动半秒计时。
func _resume() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(_attack):
		return
	_attack.update_is_attack_factors(_attack.is_enabling, AttackComponentBase.E_IsAttackFactors.Enbale)
	if _range != null:
		_range.refresh()
## [param reference] 是控制器弱引用；[param plant_ref] 与 [param attack_ref] 指向原生节点。
## [param range_effect] 保存私有范围基线；[param pulse] 标识原回调，不能清除后来新装的攻击模式。
static func _finish_exit(reference: WeakRef, plant_ref: WeakRef, attack_ref: WeakRef,
		range_effect: AdventureFumeRange, pulse: Callable) -> void:
	var controller: AdventureFumePromotionEffects = reference.get_ref() as AdventureFumePromotionEffects # 控制器可能已随母株销毁。
	if is_instance_valid(controller):
		controller._cleanup_pending = false
		if controller.is_inside_tree() and not controller.is_queued_for_deletion():
			controller._resume()
			return
	var attack: AttackComponentBulletBase = attack_ref.get_ref() as AttackComponentBulletBase # 原生组件可先于回收任务被销毁。
	if is_instance_valid(attack):
		attack.clear_continuous_attack(pulse)
	var plant: Plant011FumeShroom = plant_ref.get_ref() as Plant011FumeShroom # 仅还原仍存在的原生喷雾。
	if is_instance_valid(plant):
		plant.set_continuous_fume(false)
	if range_effect != null:
		range_effect.restore()
