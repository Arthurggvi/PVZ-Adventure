## 毁灭菇仍由原生动画与亡语使用同一个引信，转职只改变已选择的效果。
extends Plant000Base
class_name Plant016DoomShroom

## 使用原生音效、灰烬爆炸与一次性引信。
@onready var bomb_component: BombComponentNorm = %BombComponent
## 出战时冻结的特殊效果配置。
var _rules: Dictionary[String, Dictionary] = {}
## 普通僵尸与僵王各自的基础伤害加算比例。
var _base_gain: Vector2 = Vector2.ZERO
## 普通僵尸与僵王各自的最终伤害倍率。
var _final_gain: Vector2 = Vector2.ONE
## 只有需要改变伤害结算的词条才接管原生范围。
var _has_promoted_blast: bool = false
## 原生死亡回调撤销光环前冻结的引爆战场。
var _death_battle: RepeaterShotContext
## 先应用基础增幅与出战数值的主爆伤害，结算目标时再应用末乘。
var _death_damage: Vector2i

## 入树前冻结合法 [param events]，使白天首次睡眠判断读到昼。
func configure_promotions(events: Array[Dictionary]) -> void:
	for event: Dictionary in events: # 灭和涤同 kind，但基础增幅必须独立累加。
		var kind: String = event["kind"] # 其余异类词条按所属效果保存。
		if kind == "doom_damage":
			_base_gain += Vector2(float(event["normal"]), float(event["boss"]))
		elif kind == "doom_final":
			_final_gain *= Vector2(float(event["normal"]), float(event["boss"]))
		else:
			_rules[kind] = event.duplicate(true)
		_has_promoted_blast = _has_promoted_blast or kind != "doom_day"
	if _rules.has("doom_day"):
		is_sleep_in_day = false

## 等原生组件就绪后只安装一个伤害入口，音效和消耗仍由原引信完成。
func ready_norm_signal_connect() -> void:
	super()
	bomb_component.signal_bomb_once.connect(_create_crater_at_current_cell)
	if _has_promoted_blast:
		bomb_component.damage_resolver = _detonate_promoted

## 原生死亡前保存本次伤害来源与光环数值。
func character_death() -> void:
	if not is_death and _has_promoted_blast and is_instance_valid(bomb_component) and not bomb_component.is_bomb:
		_death_battle = RepeaterShotContext.from_plant(self)
		if _death_battle != null:
			_death_damage = _resolve_damage()
	super()

## 引爆时使用当前占格。昼跳过完整坑洞事务，也保留同格其他植物。
func _create_crater_at_current_cell() -> void:
	if not _rules.has("doom_day") and is_instance_valid(plant_cell):
		plant_cell.create_crater()

## 保留原生亡语入口和睡眠门禁。
func death_language() -> void:
	bomb_component.judge_death_bomb()

## 返回普通敌人和僵王各自已计入基础增幅的伤害，出战星级和光环只读一次。
func _resolve_damage() -> Vector2i:
	var base: int = bomb_component.bomb_value # 原场景的基础伤害，普通与僵王共享。
	return Vector2i(battle_damage(roundi(base * (1.0 + _base_gain.x))),
		battle_damage(roundi(base * (1.0 + _base_gain.y))))

## 进入正式战场时返回 true；缺少真实占格或阶段已失效时保留原生入口。
func _detonate_promoted() -> bool:
	var battle: RepeaterShotContext = _death_battle if _death_battle != null else RepeaterShotContext.from_plant(self) # 引信可由动画或死亡触发。
	if battle == null or not battle.is_active():
		return false
	var damage: Vector2i = _death_damage if _death_battle != null else _resolve_damage() # 原株活着时使用当前出战数值。
	AdventureDoomBlast.begin(battle, bomb_component, damage, _final_gain, _rules)
	return true
