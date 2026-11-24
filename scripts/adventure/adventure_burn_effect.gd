## 灼烧复用公共半秒伤害链，并循环播放原火豆命中特效，不借用火豆碰撞或解冻逻辑。
extends AdventurePeriodicDamageEffect
class_name AdventureBurnEffect

## 同一目标的灼烧节点名，与中毒分别拥有时限及节拍。
const NODE_NAME: StringName = &"AdventureBurnEffect"
## 原火豆和灼烧共同引用的纯视觉场景，不含子弹或伤害组件。
const IMPACT_SCENE: PackedScene = preload("res://scenes/fx/fire_pea_impact.tscn")
## 跟随目标的独立火焰视觉实例，状态结束时立即回收。
var _visual: Node2D
## 单次fire_done动画播放器，结束后在状态仍活跃时重新播放。
var _animation: AnimationPlayer

## 只有本次灼烧跳伤致死才属于烧死，目标之后被其他攻击击杀不沿用此来源。
func _damage_cause() -> CombatHitScope.DeathCause:
	return CombatHitScope.DeathCause.FIRE

## 为 [param target] 授予 [param duration] 秒灼烧；[param on_kill] 为可选真实击杀回调。
## [param source] 可为最新来源提供伤害末乘与死亡前观察。
## 重施只续时，不重复创建表现或额外伤害节拍。
static func apply_to(target: Character000Base, duration: float,
		on_kill: Callable = Callable(), source: Dictionary = {}) -> bool:
	return AdventurePeriodicDamageEffect.grant(target, duration, on_kill, NODE_NAME, AdventureBurnEffect, false, source)

## 状态首次开始时挂载纯视觉，并对齐目标的受击位置。
func _on_effect_started() -> void:
	_visual = IMPACT_SCENE.instantiate() as Node2D
	_target.add_child(_visual)
	_visual.global_position = _target.hurt_box_component.global_position
	_visual.z_index = 1
	_animation = _visual.get_node(^"AnimationPlayer") as AnimationPlayer
	_animation.animation_finished.connect(_on_visual_finished)
	_animation.play(&"fire_done")

## [param _animation_name] 为刚播放完的原生动画；同一实例循环，不逐跳堆积新节点。
func _on_visual_finished(_animation_name: StringName) -> void:
	if _remaining > 0.0 and _battle_active() and is_instance_valid(_animation):
		_animation.play(&"fire_done")

## 撤销本状态的视觉，保留中毒、寒冷和其他状态的表现。
func _on_effect_cleared() -> void:
	if is_instance_valid(_visual):
		_visual.queue_free()
	_visual = null
	_animation = null
