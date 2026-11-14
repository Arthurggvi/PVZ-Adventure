## 火爆辣椒的转职随出战卡冻结，仍由原生动画或亡语触发同一个引信。
extends Plant000Base
class_name Plant021Jalapeno

## 原生引爆组件，同时负责音效和防重入。
@onready var bomb_component: BombComponentJalapeno = %BombComponent
## 本株对应的独立出战卡。
var promotion_card_uid: String
## 已选效果的集合；为空时沿用原版整行事件。
var promotion_rules: Dictionary[String, bool] = {}
## 死亡信号撤销光环前冻结的主爆、地火伤害；空数组表示仍可用当前出战值。
var death_fire_damage: Array[int] = []

## 入树前冻结 [param uid] 和 [param events]，无须访问尚未就绪的组件。
func configure_promotions(uid: String, events: Array[Dictionary]) -> void:
	promotion_card_uid = uid
	for event: Dictionary in events: # 书目已完成同阶互斥校验。
		promotion_rules[String(event.kind)] = true

## 返回本次主爆与地火的最终伤害；涤荡改基础值，业火在出战修正后结算。
func resolve_fire_damage() -> Array[int]:
	var base_scale: int = 2 if promotion_rules.has("jalapeno_purge") else 1 # 涤荡只修正基础伤害。
	var last_scale: int = 2 if promotion_rules.has("jalapeno_inferno") else 1 # 业火在整数出战伤害后再乘。
	return [battle_damage(bomb_component.bomb_value * base_scale) * last_scale, battle_damage(40 * base_scale) * last_scale]

## 在死亡信号可能撤销出战加成前保留本次火焰伤害。
func character_death() -> void:
	if not is_death and not promotion_rules.is_empty() and is_instance_valid(bomb_component) and not bomb_component.is_bomb:
		death_fire_damage = resolve_fire_damage()
	super()

## 亡语仍使用原生组件的单次引爆保护。
func death_language():
	bomb_component.judge_death_bomb()
