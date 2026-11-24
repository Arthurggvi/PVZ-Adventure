## 单株辣椒消耗后，由战场持有地火、灼烧归因与涅槃时限。
extends Node
class_name AdventureJalapenoBlast

## 本次爆炸所属的战场。
var _game: MainGameManager
## 保留攻击的棋盘身份与几何。
var _board: BoardRuntime
## 后续效果不可越过出手时的轮次。
var _round: int
## 同关内普通和噩梦阶段也各自隔离。
var _phase: StagePhaseDefinition
## 完整行与额外纵列共用的命中范围。
var _footprint := AdventureJalapenoFootprint.new()
## 冻结的独立出战卡 UID。
var _uid: String
## 已选择的效果集合。
var _rules: Dictionary[String, bool]
## 已结算出战修饰的主爆及地火伤害。
var _damage: Array[int]
## 原生可命中的僵尸状态位，用于额外纵列的受击筛选。
var _statuses: int
## 已记功的死亡身份；同一实际死者只能引燃邻敌一次。
var _credited: Dictionary[int, bool] = {}
## 死亡前的世界位置，包含实际接伤的保护者。
var _death_points: Dictionary[int, Vector2] = {}
## 由当前帧收集的死亡位置，下一次处理后清空。
var _ignitions: Array[Vector2] = []
## 本次授予无敌的组件引用；以独立来源解除。
var _protected: Array[HpComponent] = []
## 暂停不流逝的战斗秒数，从引爆开始。
var _elapsed: float = 0.0
## 下一跳地火所在的战斗秒数。
var _next_tick: float = 0.5
## 最后一次成功施加的灼烧到期秒数。
var _burn_until: float = 0.0

## 由原生引信调用。[param plant] 提供出战快照，[param statuses] 为原生爆炸受击位。
## 成功接管返回 true；缺少正式战场或种植点时交还原生路径。
static func try_detonate(plant: Plant021Jalapeno, statuses: int) -> bool:
	var game: MainGameManager = Global.main_game # 只接管当前实际战场。
	if not is_instance_valid(game) or not game.is_ancestor_of(plant) or not is_instance_valid(plant.plant_cell) \
			or game.board == null or plant.plant_cell.board != game.board \
			or game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		return false
	var blast := AdventureJalapenoBlast.new() # 母株消费后，战场仍持有本次效果。
	blast._game = game
	blast._board = game.board
	blast._round = game.curr_game_round
	blast._phase = AdventureSession.get_active_phase(game.game_para)
	blast._uid = plant.promotion_card_uid
	blast._rules = plant.promotion_rules.duplicate()
	blast._damage = plant.resolve_fire_damage() if plant.death_fire_damage.is_empty() else plant.death_fire_damage
	blast._statuses = statuses
	blast._footprint.configure(plant.plant_cell, blast._rules.has("jalapeno_wildfire"), blast._rules.has("jalapeno_fire_tongue"))
	game.bombs.add_child(blast)
	blast._detonate(plant.bomb_component.boss_blast_damage_cap())
	return true

## 直接复用普通灰烬爆炸、设施穿透及僵王辣椒入口，然后执行选中的后续效果。
## [param boss_damage_cap] 仅限制本次主爆对僵王的伤害。
func _detonate(boss_damage_cap: int) -> void:
	TreePauseManager.pause_factors_changed.connect(_check_boundary)
	EventBus.subscribe("main_game_progress_update", _on_progress)
	_footprint.display(_rules.has("jalapeno_combustion"))
	var scope := CombatHitScope.new() # 原生转伤之后才消费同一爆炸的受击资格。
	scope.before_death = _remember_death_point
	for target: Character000Base in _footprint.enemies(_game, true): # 同时纳入普通僵尸、僵王和设施。
		if not _active():
			break
		if not _footprint.can_hit(target, _game):
			continue
		if target is ZB000Base:
			_remember_death_point(target)
			target.be_jalapeno(_damage[0], boss_damage_cap)
			if target.is_death:
				_on_kill(target)
		elif _footprint.touches(target) and (_footprint.rows.has(target.lane) or not target is Zombie000Base or (target.curr_be_attack_status & _statuses) != 0):
			if target is Zombie000Base:
				_on_kill(target.be_bomb(_damage[0], true, 1.0, scope))
			else:
				target.be_attacked_bullet(_damage[0], BulletRegistry.AttackMode.Penetration, false, false)
	_death_points.clear()
	if _active() and _rules.has("jalapeno_nirvana"):
		AdventureJalapenoNirvana.apply(_footprint.cells, _damage[0], get_instance_id(), _protected, _active)
	if not _active() or (not _rules.has("jalapeno_combustion") and _protected.is_empty()):
		_finish()

## 在扣除致死生命前，记录实际承伤者 [param target] 的落点。
func _remember_death_point(target: Character000Base) -> void:
	_death_points[target.get_instance_id()] = AdventureJalapenoFootprint.hit_center(target)

## 只处理实际杀死的 [param casualty]；奖励来源是出手卡，与母株存亡无关。
func _on_kill(casualty: Character000Base) -> void:
	if not is_instance_valid(casualty) or not casualty.is_death or not _same_battle():
		return
	var identity: int = casualty.get_instance_id() # 同尸只奖励、传播一次。
	if _credited.has(identity):
		return
	_credited[identity] = true
	if _rules.has("jalapeno_combustion") and _active():
		var point: Vector2 = _death_points[identity] if _death_points.has(identity) else AdventureJalapenoFootprint.hit_center(casualty) # 原生路由已优先保存死亡前位置。
		_ignitions.append(point)
	_death_points.erase(identity)
	if _rules.has("jalapeno_reaper") and is_instance_valid(_game.card_manager):
		var slots: CardSlotBattle = _game.card_manager.card_slot_battle # 以 UID 找到出手的唯一卡槽。
		var card: Card = slots.find_plant_card_by_uid(_uid) if is_instance_valid(slots) else null # 卡离场时不记给同种卡。
		if is_instance_valid(card):
			card.adventure_adjust_remaining_cooldown(-1.0)

## [param delta] 为战斗秒数；每帧排空已去重的死亡队列，传播只加状态，不同步扣血。
func _physics_process(delta: float) -> void:
	if not _active():
		_finish()
		return
	_elapsed += delta
	if _elapsed >= 2.0 and not _protected.is_empty():
		AdventureJalapenoNirvana.release(get_instance_id(), _protected)
	while _rules.has("jalapeno_combustion") and _next_tick <= minf(5.0, _elapsed + 0.00001) and _active():
		_next_tick += 0.5
		_burn_ground()
		if _next_tick > 5.0:
			_footprint.clear_ground()
	_spread_burn()
	if _protected.is_empty() and (_next_tick > 5.0 or not _rules.has("jalapeno_combustion")) and _elapsed > _burn_until + 0.5:
		_finish()

## 地火每半秒从接触者读取现有受击资格，以普通伤害经过护甲及保护者。
func _burn_ground() -> void:
	var scope := CombatHitScope.for_cause(CombatHitScope.DeathCause.FIRE) # 同一跳只伤实际承伤者一次，并携带地火死因。
	scope.before_death = _remember_death_point
	for target: Character000Base in _footprint.enemies(_game): # 接触范围按此刻平台世界位置重新判断。
		if not _active():
			break
		if not _footprint.can_hit(target, _game) or not _footprint.touches(target):
			continue
		if target is Zombie000Base:
			if target.curr_be_attack_status != Zombie000Base.E_BeAttackStatusZombie.IsNorm \
					or (is_instance_valid(target.move_component) and target.move_component.is_forced_airborne()):
				continue
			_on_kill((target.hp_component as HpComponentZombie).apply_hit(_damage[1], BulletRegistry.AttackMode.Norm, true, false, true, 1.0, 0, -1, null, scope))
		else:
			_remember_death_point(target)
			target.be_attacked_bullet(_damage[1], BulletRegistry.AttackMode.Norm, true, false)
			if target.is_death:
				_on_kill(target)
		if _footprint.can_hit(target, _game) and _active():
			_apply_burn(target)
	_death_points.clear()

## 把已确认的死亡扩散给附近有效敌人；同批每个邻敌至多刷新一次公共灼烧。
func _spread_burn() -> void:
	if _ignitions.is_empty() or not _active():
		return
	_footprint.spread_burn(_game, _ignitions, _apply_burn)
	_ignitions.clear()

## 刷新 [param target] 的两秒公共灼烧并保留本次来源。
func _apply_burn(target: Character000Base) -> void:
	if _active() and AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.BURN, 0, 2.0, 0.0, {
			"on_kill": _on_kill, "before_death": _remember_death_point, "source_active": _active,
			"final_multiplier": 2.0 if _rules.has("jalapeno_inferno") else 1.0}):
		_burn_until = _elapsed + 2.0

## 核对冻结的战场身份；最后一击同步结束战斗时仍可归还冷却。
func _same_battle() -> bool:
	return is_inside_tree() and is_instance_valid(_game) and not _game.is_queued_for_deletion() \
		and Global.main_game == _game and get_tree().current_scene == _game and _game.board == _board \
		and _game.curr_game_round == _round and AdventureSession.get_active_phase(_game.game_para) == _phase

## 后续伤害和治疗要求当前战斗仍在进行。
func _active() -> bool:
	return _same_battle() and not is_queued_for_deletion() \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.ReChooseCard, false)

## [param _progress] 为刚提交的进度，复核战局并同步释放结束时仍存续的效果。
func _on_progress(_progress: int) -> void:
	_check_boundary()

## 暂停因素变化时同步检查边界；普通菜单暂停保留剩余战斗秒数。
func _check_boundary() -> void:
	if not _active():
		_finish()

## 立即解除本来源无敌，再排队移除地火控制器。
func _finish() -> void:
	AdventureJalapenoNirvana.release(get_instance_id(), _protected)
	_footprint.clear_ground()
	queue_free()

## 场景直接卸载时也释放本来源和地火。
func _exit_tree() -> void:
	AdventureJalapenoNirvana.release(get_instance_id(), _protected)
	_footprint.clear_ground()
	EventBus.unsubscribe("main_game_progress_update", _on_progress)
