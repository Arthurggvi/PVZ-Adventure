## 三线射手的洪流叠种只强化原株；弹道由原生攻击动画统一派发。
extends Plant000Base
class_name Plant019ThreePeater

## 生命成长与发数上限和技能书共用。
const Books = preload("res://scripts/adventure/research/research_threepeater_promotion_books.gd")
## 补种后的原株净化表现，无需加载外部图像。
const ReinforceFx = preload("res://scripts/fx/three_pea_reinforce_fx.gd")
## 兼容读档及复生的洪流字段。
const FLOOD_SAVE_KEY: String = "threepeater_flood"

## 绑定本株原生发射和攻速信号。
@onready var attack_component: AttackComponentBulletThreePea = $AttackComponent
## 洪流卡牌 UID；空值表示不接受叠种。
var _flood_uid: String = ""
## 已成功强化的次数，不含最初的植物。
var _flood_stacks: int = 0
## 第一次强化时的实际生命上限，含星级和复生修正。
var _base_max_health: int = 0
## 陷阵、鏖战和封锁在洪流前合计增加的每路发数。
var _bonus_shots: int = 0
## 单株复用的补种效果，只有播放时更新。
var _reinforce_fx: Node2D

## 初始化正常出战角色信号连接。
func ready_norm_signal_connect():
	super()
	signal_update_speed.connect(attack_component.owner_update_speed)

## 在入树前为 [param card_uid] 冻结 [param events]，叠种与弹道使用同一套参数。
func configure_promotions(card_uid: String, events: Array[Dictionary]) -> void:
	var attack: AttackComponentBulletThreePea = get_node(^"AttackComponent") # 此时 onready 变量尚未初始化。
	for rule: Dictionary in events: # 发数修饰叠加，弹种和命中效果由真实组件消费。
		_bonus_shots += int(rule.get("extra", 0))
		match str(rule.kind):
			"threepeater_laser":
				attack.laser_enabled = true
			"threepeater_flood":
				_flood_uid = card_uid
			"threepeater_kinetic":
				attack.kinetic_enabled = true
			"threepeater_finisher":
				attack.finisher_cap = int(rule.cap)
			"threepeater_assault", "threepeater_siege", "threepeater_sunder", "threepeater_lockdown":
				attack.configure_impact(rule)

## 当前齐射每条逻辑弹道的发数，边路折返后才并入同路。
func shots_per_ray() -> int:
	return mini(Books.MAX_SHOTS_PER_RAY, 1 + _bonus_shots + _flood_stacks)

## 验证 [param card_uid] 对应的原株仍可强化；禁种等地形要求由种植条件检查。
func can_reinforce(card_uid: String) -> bool:
	return not _flood_uid.is_empty() and _flood_uid == card_uid and is_node_ready() and is_inside_tree() \
		and not is_death and not is_queued_for_deletion() and not is_being_relocated \
		and not hp_component.is_death and shots_per_ray() < Books.MAX_SHOTS_PER_RAY

## 同步用 [param card_uid] 给本株叠一层；保留占位和正面效果，清负面后按新上限回满血。
func reinforce(card_uid: String) -> bool:
	if not can_reinforce(card_uid):
		return false
	if _flood_stacks == 0:
		_base_max_health = hp_component.max_hp
	_flood_stacks += 1
	hp_component.max_hp = _flood_max_health(_base_max_health, _flood_stacks)
	AdventurePlantNegativeEffects.purge(self)
	hp_component.heal(hp_component.max_hp)
	if not is_instance_valid(_reinforce_fx):
		_reinforce_fx = ReinforceFx.new()
		body.add_child(_reinforce_fx)
	_reinforce_fx.pulse()
	return true

## 用 [param base] 和 [param stacks] 计算线性增长后的生命上限。
static func _flood_max_health(base: int, stacks: int) -> int:
	return roundi(base * (1.0 + Books.HEALTH_PER_STACK * stacks))

## 保存已提交的叠种事实，旧档或未叠种的植物继续采用基础格式。
func gat_save_game_data_plant() -> Dictionary:
	var saved: Dictionary = super() # 保留当前本体血量及基础字段。
	if _flood_stacks > 0:
		saved[FLOOD_SAVE_KEY] = {"stacks": _flood_stacks, "base_max": _base_max_health}
	return saved

## 离树检查 [param state]。叠种记录需要合法发数和可兑现的上限。
func accepts_save_state(state: Dictionary) -> bool:
	if not super(state):
		return false
	if not state.has(FLOOD_SAVE_KEY):
		return true
	var entry: Variant = state[FLOOD_SAVE_KEY] # 非法对象不能被当作洪流数据。
	if not entry is Dictionary or not entry.get("stacks") is int or not entry.get("base_max") is int:
		return false
	var count: int = entry["stacks"] # 最高发数仍包含已经配置的全部额外发数。
	var base: int = entry["base_max"] # 原株初次生效时的最大生命。
	return count > 0 and count < Books.MAX_SHOTS_PER_RAY - _bonus_shots \
		and base > 0 and base <= PlantCardInstance.MAX_JSON_INTEGER \
		and int(state["curr_hp"]) <= _flood_max_health(base, count)

## 从已校验的 [param state] 还原已付费叠种。复生按该次折减后的配方重算基线。
func load_game_data_plant(state: Dictionary):
	var restored: Dictionary = state # 普通读档不修改调用方数据。
	if state.has(FLOOD_SAVE_KEY):
		var entry: Dictionary = state[FLOOD_SAVE_KEY] # 预检后的纯数据。
		_flood_stacks = entry["stacks"]
		_base_max_health = entry["base_max"]
		var reviving: bool = revival_health_scale < 1.0 and not state.has("revival_max_health") # 复生流程已设置本次配方上限。
		if reviving:
			_base_max_health = hp_component.max_hp
			restored = state.duplicate()
		hp_component.max_hp = _flood_max_health(_base_max_health, _flood_stacks)
		if reviving:
			restored["curr_hp"] = hp_component.max_hp
	super(restored)
