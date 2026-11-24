## 每只僵尸持有一个临时加速通道，各来源独立计时，只应用最高倍率。
## 换行保留计时。节点随僵尸销毁，速度更新只在战斗生命周期内发生。
extends Node
class_name AdventureZombieTimedSpeedBoost

const NODE_NAME: StringName = &"AdventureTimedSpeedBoost"
var _zombie: Character000Base
var _active: Array[Dictionary] = []
var _applied_multiplier := 1.0

## [param target] 获得 [param multiplier] 倍、持续 [param duration] 秒的加速；[param tier_owned] 标记目标自身等阶技能。
static func apply_to(target: Character000Base, multiplier: float, duration: float, tier_owned: bool = false) -> void:
	if not is_instance_valid(target) or target.is_death or target.is_hypno 			or target.is_queued_for_deletion() or multiplier <= 1.0 or duration <= 0.0:
		return
	var boost: AdventureZombieTimedSpeedBoost = target.get_node_or_null(
			NodePath(NODE_NAME)) as AdventureZombieTimedSpeedBoost
	if boost == null:
		boost = AdventureZombieTimedSpeedBoost.new()
		boost.name = NODE_NAME
		target.add_child(boost)
	boost.grant(multiplier, duration, tier_owned)

func _ready() -> void:
	_zombie = get_parent() as Character000Base
	set_process(false)
	if _zombie != null:
		_zombie.signal_character_death.connect(_clear_boosts)
		_zombie.signal_character_be_hypno.connect(_clear_boosts)
		if _zombie is Zombie000Base:
			(_zombie as Zombie000Base).signal_tier_skills_changed.connect(_on_tier_changed)

## 同 [param multiplier]、同 [param tier_owned] 的奖励只保留最晚到期时间。
## [param duration] 为此加速的持续秒数。
func grant(multiplier: float, duration: float, tier_owned: bool = false) -> void:
	if _zombie == null or _zombie.is_death or multiplier <= 1.0 or duration <= 0.0:
		return
	for effect: Dictionary in _active: # 同归属等倍率的时钟受同一沉默规则控制。
		if float(effect["multiplier"]) == multiplier and bool(effect["tier_owned"]) == tier_owned:
			effect["remaining"] = maxf(float(effect["remaining"]), duration)
			return
	_active.append({"multiplier": multiplier, "remaining": duration, "tier_owned": tier_owned})
	_sync_speed()
	set_process(true)

## 推进 [param delta] 游戏秒，倍率仅在授予、到期或状态变化时合成。
func _process(delta: float) -> void:
	if not is_instance_valid(_zombie) or _zombie.is_death or _zombie.is_hypno:
		_clear_boosts()
		return
	var expired := false # 记录本帧是否需要重新选择生效倍率。
	for index: int in range(_active.size() - 1, -1, -1): # 倒序允许原地移除已到期记录。
		var effect: Dictionary = _active[index] # 沉默期间自身等阶加速保持剩余秒数。
		if _effect_suppressed(effect):
			continue
		effect["remaining"] = float(effect["remaining"]) - delta
		if float(effect["remaining"]) <= 0.0:
			_active.remove_at(index)
			expired = true
	if expired:
		_sync_speed()
		set_process(not _active.is_empty())

func _sync_speed() -> void:
	var multiplier := 1.0
	for effect: Dictionary in _active: # 外部加速继续有效，自己的等阶加速按当前资格合成。
		if not _effect_suppressed(effect):
			multiplier = maxf(multiplier, float(effect["multiplier"]))
	if not is_equal_approx(multiplier, _applied_multiplier):
		_applied_multiplier = multiplier
		_zombie.update_speed_factor(multiplier,
				Character000Base.E_Influence_Speed_Factor.AdventureTierBoost)

## [param effect] 是否因自身等阶沉默被遮蔽；施法者已经授予的外部奖励独立保留。
func _effect_suppressed(effect: Dictionary) -> bool:
	return bool(effect.get("tier_owned", false)) and _zombie is Zombie000Base \
		and not (_zombie as Zombie000Base).are_tier_skills_active()

## [param _active] 变化时即时重算输出，不重启任一计时。
func _on_tier_changed(_active: bool) -> void:
	_sync_speed()

## 死亡或魅惑时结束加速计时；仍存活的魅惑僵尸恢复原有速度。
func _clear_boosts() -> void:
	_active.clear()
	set_process(false)
	if is_instance_valid(_zombie) and not _zombie.is_death:
		_applied_multiplier = 1.0
		_zombie.update_speed_factor(1.0,
				Character000Base.E_Influence_Speed_Factor.AdventureTierBoost)
