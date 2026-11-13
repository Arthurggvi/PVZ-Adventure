## 单颗回旋镖的纯伤害规则与成长计数；主伤和追猎附伤分开，避免来源倍率重复放大。
extends RefCounted
class_name BloomerangDamage

## 每次有效命中增加的主伤倍率，零表示未获得回旋苍镰。
var _growth_step: float = 0.0
## 主伤最终倍率上限；首击始终从一倍开始。
var _growth_cap: float = 1.0
## 命中前本体已损生命转为附伤的比例；不读取防具或临时护甲。
var _missing_health_fraction: float = 0.0
## 僵王附伤上限占最大本体生命的比例，交给生命组件在劣化后限制。
var _boss_cap_fraction: float = 0.0
## 本弹已接受的成长次数；折返不清空，达到上限后不再增加。
var _growth_hits: int = 0

## [param shot] 为发射时冻结的规则；每枚新弹单独配置，弱镖与补投不继承母弹成长。
## 基础伤害减半已在子弹初始化时应用，本类不会再次缩减弱镖的主伤或追猎。
func configure(shot: BloomerangShotContext) -> void:
	_growth_hits = 0
	_growth_step = maxf(0.0, shot.growth_step) if is_finite(shot.growth_step) else 0.0
	_growth_cap = maxf(1.0, shot.growth_cap) if is_finite(shot.growth_cap) else 1.0
	_missing_health_fraction = clampf(shot.missing_health_fraction, 0.0, 1.0) if is_finite(shot.missing_health_fraction) else 0.0
	_boss_cap_fraction = clampf(shot.boss_bonus_cap_fraction, 0.0, 1.0) if is_finite(shot.boss_bonus_cap_fraction) else 0.0

## [param base_damage] 已包含卡片和本弹基础系数的主伤；只按累计百分点成长，不复乘上一次攻值。
func primary_damage(base_damage: int) -> int:
	var factor: float = minf(_growth_cap, 1.0 + float(_growth_hits) * _growth_step) # 当前击使用之前已累计的成长。
	return maxi(0, roundi(float(base_damage) * factor))

## [param enemy] 为直接命中目标；只对普通僵尸与僵王附伤，设施和植物返回零。
## 返回原始附伤与其上限；本次主伤还未扣除，保护者接收这份冻结结果。
func bonus_for(enemy: Character000Base) -> Vector2i:
	if _missing_health_fraction <= 0.0 or not is_instance_valid(enemy) \
			or not (enemy is Zombie000Base or enemy is ZB000Base):
		return Vector2i(0, -1)
	var health: HpComponent = enemy.hp_component # 只读取本体血池，不能用包含防具的 get_all_hp。
	if not is_instance_valid(health) or health.max_hp <= 0:
		return Vector2i(0, -1)
	var missing: int = maxi(0, health.max_hp - health.curr_hp) # 命中前已损本体生命。
	var bonus: int = floori(float(missing) * _missing_health_fraction) # 不接受卡片、苍镰或弱镖基础倍率的再次修正。
	var cap: int = floori(float(health.max_hp) * _boss_cap_fraction) if enemy is ZB000Base else -1 # 向下取整保证不超过僵王比例帽。
	return Vector2i(bonus, cap)

## 仅由接受命中的 impact_resolved 回调调用；免疫或格挡仍是命中，重复受击框不能进入此处。
func register_impact() -> void:
	if _growth_step > 0.0 and 1.0 + float(_growth_hits) * _growth_step < _growth_cap:
		_growth_hits += 1
