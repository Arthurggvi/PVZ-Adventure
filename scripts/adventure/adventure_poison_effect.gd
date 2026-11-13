## 通用中毒状态：每半秒按本体最大生命结算普通伤害，生命周期跟随目标。
## 同一目标只保留一个毒伤节拍；重施刷新剩余时长，最新来源接管后续击杀归属。
extends Node
class_name AdventurePoisonEffect

## 同一角色复用的中毒节点名，避免每次命中另建计时器。
const NODE_NAME: StringName = &"AdventurePoisonEffect"
## 两次毒伤之间的战斗秒数，不受目标动作速度影响。
const TICK_SECONDS: float = 0.5
## 每跳基础伤害占目标本体最大生命的比例，防具不计入分母。
const MAX_HEALTH_FRACTION: float = 0.02
## 时限容差，保证整秒到期时不会漏掉最后一跳。
const TIME_EPSILON: float = 0.00001

## 中毒的角色；目标死亡、魅惑或离开本轮战斗时停止结算。
var _target: Character000Base
## 授予中毒时的战场，防止旧场景继续造成伤害。
var _game: MainGameManager
## 授予中毒时的轮次，换轮后不保留中毒。
var _round: int = -1
## 剩余中毒战斗秒数；0 表示休眠，可由后续命中重新启用。
var _remaining: float = 0.0
## 距下一跳的战斗秒数，刷新状态时保留当前相位。
var _until_tick: float = TICK_SECONDS
## 最新来源的击杀回调；接收本次伤害实际杀死的角色，不持有植物节点。
var _on_kill: Callable = Callable()


## [param target] 正常出战的存活目标；[param duration] 为中毒秒数，须有限且为正。
## [param on_kill] 是可选击杀回调，以实际死亡角色为参数；不接受实例外的全局计时。
## 成功授予或刷新时返回 true；失效目标、非当前战场或已结束战斗返回 false。
static func apply_to(target: Character000Base, duration: float,
		on_kill: Callable = Callable()) -> bool:
	if not is_instance_valid(target) or target.is_death or target.is_hypno \
			or target.is_queued_for_deletion() or not target.is_inside_tree() \
			or target.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
			or not is_finite(duration) or duration <= 0.0 \
			or not is_instance_valid(target.hp_component) or target.hp_component.max_hp <= 0:
		return false
	var game: MainGameManager = Global.main_game # 目标必须仍属于本次活动战场。
	if not is_instance_valid(game) or game.is_queued_for_deletion() or not game.is_ancestor_of(target) \
			or game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		return false
	var effect := target.get_node_or_null(NodePath(NODE_NAME)) as AdventurePoisonEffect # 目标独享的状态。
	if effect == null:
		effect = AdventurePoisonEffect.new()
		effect.name = NODE_NAME
		effect._target = target
		target.add_child(effect)
	effect._game = game
	effect._round = game.curr_game_round
	effect.refresh(duration, on_kill)
	return true


## 默认继承角色的暂停/禁用状态；死亡与魅惑立即停止毒伤，节点随角色一并释放。
func _ready() -> void:
	set_physics_process(false)
	_target.signal_character_death.connect(clear)
	_target.signal_character_be_hypno.connect(clear)


## [param duration] 为本次刷新秒数；[param on_kill] 是本次来源的击杀回调。
## 活跃状态只延长到两者较大值，不叠加伤害、不推迟下一跳。
func refresh(duration: float, on_kill: Callable) -> void:
	if _remaining <= 0.0:
		_until_tick = TICK_SECONDS
	_remaining = maxf(_remaining, duration)
	_on_kill = on_kill
	set_physics_process(true)


## [param delta] 是随场景暂停的战斗秒数；冰冻动作速度不改变中毒的真实持续时长。
func _physics_process(delta: float) -> void:
	if not _battle_active():
		clear()
		return
	var active_delta: float = minf(_remaining, delta) # 到期后的帧余量不能产生额外毒伤。
	_remaining -= active_delta
	_until_tick -= active_delta
	while _until_tick <= TIME_EPSILON and _battle_active():
		_until_tick += TICK_SECONDS
		_deal_tick()
	if _remaining <= TIME_EPSILON:
		clear()


## 返回本轮是否仍可结算毒伤；目标死亡、阵营变化与切场均停止后续跳数。
func _battle_active() -> bool:
	return is_instance_valid(_target) and not _target.is_death and not _target.is_hypno \
		and not _target.is_queued_for_deletion() and _target.is_inside_tree() \
		and is_instance_valid(_game) and not _game.is_queued_for_deletion() \
		and _game == Global.main_game and _game.curr_game_round == _round \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME


## 单跳经过既有格挡、减伤、防具和转移路径；僵王仍由自己的受击窗口决定是否扣血。
func _deal_tick() -> void:
	var hp: HpComponent = _target.hp_component # 最大生命来自本体池，不能用当前血量或防具血量。
	if not is_instance_valid(hp) or hp.is_death:
		return
	var damage: int = maxi(0, roundi(float(hp.max_hp) * MAX_HEALTH_FRACTION)) # 按整点伤害规则取整。
	if damage <= 0:
		return
	var callback: Callable = _on_kill # 扣血可能同步触发 clear，先保留本次归属。
	var casualty: Character000Base = null # 普通僵尸可能把伤害转移给另一个实际死亡者。
	if _target is Zombie000Base and hp is HpComponentZombie:
		casualty = (hp as HpComponentZombie).apply_hit(damage, BulletRegistry.AttackMode.Norm, true, false)
	else:
		_target.be_attacked_bullet(damage, BulletRegistry.AttackMode.Norm, true, false)
		if is_instance_valid(_target) and _target.is_death:
			casualty = _target
	if is_instance_valid(casualty) and callback.is_valid():
		callback.call(casualty)


## 结束当前中毒并释放来源回调；保留休眠节点以供同一角色后续复用。
func clear() -> void:
	_remaining = 0.0
	_until_tick = TICK_SECONDS
	_on_kill = Callable()
	set_physics_process(false)


## 离树时丢弃来源回调，不允许场景外继续持有本轮状态。
func _exit_tree() -> void:
	clear()
