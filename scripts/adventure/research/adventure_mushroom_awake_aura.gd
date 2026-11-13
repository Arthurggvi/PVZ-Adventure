## 月光蔓延只提供原生睡眠豁免；扫描、无效化与退出回收由公共蘑菇光环管理。
extends AdventureMushroomAura
class_name AdventureMushroomAwakeAura

## [param plant] 为持有月光蔓延的真实植株；本控制器在入树前配置并挂在该植株下。
func configure(plant: Plant000Base) -> void:
	configure_aura(plant, AdventureMushroomAwakeAura._accept_sleep,
		AdventureMushroomAwakeAura._set_awake)

## [param target] 已通过公共蘑菇身份和战场校验；只有原生睡眠组件存在时才接收豁免。
static func _accept_sleep(target: Plant000Base) -> bool:
	return is_instance_valid(target.sleep_component)

## [param target] 为真实受益者；[param source_id] 独立区分重叠光环；[param enabled] 授予或撤销。
## 仅改临时唤醒来源，保留咖啡豆、夜晚与目标自身的常醒转职。
static func _set_awake(target: Plant000Base, source_id: int, enabled: bool) -> void:
	if is_instance_valid(target.sleep_component):
		target.sleep_component.set_awake_source(source_id, enabled)
