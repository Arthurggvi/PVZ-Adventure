## 冥镰点燃真实承伤者，复用半秒节拍与火焰生命周期，保留独立的定额伤害。
extends AdventureBurnEffect
class_name UnemployedReaperBurn

## 独立状态槽，植物的百分比灼烧不会覆盖此定额来源。
const REAPER_BURN_NODE: StringName = &"UnemployedReaperBurn"
## 灼烧持续的战斗秒数，结算到第六跳。
const BURN_SECONDS: float = 3.0
## 每半战斗秒送入既有伤害管线的基础整数。
const TICK_DAMAGE: int = 20
## 火焰共享无参数的紫色材质，灼烧淡出由各自的画布颜色控制。
const TINT_MATERIAL: ShaderMaterial = preload("res://resources/adventure/skills/unemployed_reaper_burn_material.tres")

## 在 [param battle] 内为仍存活的 [param target] 登记定额灼烧。
static func ignite(target: Character000Base, battle: RepeaterShotContext) -> void:
	var source_active: Callable = func() -> bool: return battle.is_active() # 捕获战局快照，斩击画布离树后仍可结算剩余灼烧。
	AdventurePeriodicDamageEffect.grant(target, BURN_SECONDS, Callable(), REAPER_BURN_NODE,
		UnemployedReaperBurn, false, {"source_active": source_active})

## [param _max_hp] 不影响冥镰的定额伤害。
func _base_tick_damage(_max_hp: int) -> int:
	return TICK_DAMAGE

## 复用单个火焰循环并应用共享配色材质。
func _on_effect_started() -> void:
	super()
	for part: Node in _visual.get_node(^"Body").get_children(): # 只为动画的绘制层着色。
		if part is Sprite2D:
			part.material = TINT_MATERIAL

## [param delta] 为战斗秒数；最后 0.32 秒逐步收暗火焰，末跳仍正常结算。
func _physics_process(delta: float) -> void:
	super(delta)
	if is_instance_valid(_visual):
		_visual.modulate.a = smoothstep(0.0, 0.32, _remaining)
