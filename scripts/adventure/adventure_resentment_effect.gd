## 缠怨永久保留一个每秒节拍；黑白明度随战斗时间平滑交替，不覆盖其他滤镜。
extends AdventurePeriodicDamageEffect
class_name AdventureResentmentEffect

## 同一目标唯一的缠怨节点，重复命中只更新归属。
const NODE_NAME: StringName = &"AdventureResentmentEffect"
## 黑白一个往返周期的战斗秒数。
const PULSE_SECONDS: float = 0.9
## 渐入用的战斗时间，同时作为周期相位，重施不重启。
var _visual_time: float = 0.0

## 为 [param target] 授予永久缠怨；[param on_kill] 接收本状态实际造成的死亡者。
## 不累加跳伤、不刷新下一跳；真正离场、魅惑和本战局结束均清除。
static func apply_to(target: Character000Base, on_kill: Callable = Callable()) -> bool:
	if not is_instance_valid(target) or not (target is Zombie000Base or target is ZB000Base):
		return false
	return AdventurePeriodicDamageEffect.grant(target, 0.0, on_kill, NODE_NAME, AdventureResentmentEffect, true)

## 缠怨每一战斗秒结算一次，中毒与灼烧的默认半秒逻辑保持不变。
func _tick_seconds() -> float:
	return 1.0

## 初次激活只重置视觉相位，纯视觉不改变攻击节拍。
func _on_effect_started() -> void:
	_visual_time = 0.0

## [param delta] 为可暂停的战斗秒数；先让统一父类结算生命周期和伤害，再更新明度。
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_effect_active() or not is_instance_valid(_target.body):
		return
	_visual_time += delta
	var wave: float = 0.5 - 0.5 * cos(_visual_time * TAU / PULSE_SECONDS) # 正弦曲线平滑连接黑与白。
	var brightness: float = lerpf(0.12, 2.8, wave) # 保留原轮廓细节，明亮峰值形成白光闪烁。
	var entrance: float = smoothstep(0.0, 0.18, _visual_time) # 初次附着逐渐入场，避免整块颜色硬跳。
	brightness = lerpf(1.0, brightness, entrance)
	_target.body.set_other_color(BodyCharacter.E_ChangeColors.Resentment, Color(brightness, brightness, brightness))

## 清除时仅恢复本状态的颜色因素；不能冲掉寒冷、劣化及其他明暗效果。
func _on_effect_cleared() -> void:
	if is_instance_valid(_target) and is_instance_valid(_target.body):
		_target.body.set_other_color(BodyCharacter.E_ChangeColors.Resentment, Color.WHITE)
