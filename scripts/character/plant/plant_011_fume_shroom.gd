## 原生大喷菇；动画喷雾与持续喷雾共用同一组粒子，持续模式不重复重启动画。
extends Plant000Base
class_name Plant011FumeShroom

## 原生索敌、攻击时钟及射击参数入口。
@onready var attack_component: AttackComponentBulletBase = $AttackComponent
## 与原射击动画绑定的喷雾容器。
@onready var bullet_fx: Node2D = %Bullet_FX
## 原生喷雾粒子列表，范围投影只调整其行程和数量。
var all_bullet_fx: Array[GPUParticles2D] = []
## 持续模式独占喷雾启停，旧动画方法轨道不能提前停止或重新启动它。
var _continuous_fume: bool = false

## 正常战斗就绪后登记原生粒子，展示或花园仍保留原生命周期。
func ready_norm():
	super()
	for particles: GPUParticles2D in bullet_fx.get_children(): # 本场景喷雾容器只包含原生GPU粒子。
		all_bullet_fx.append(particles)

## 保留角色原有速度到攻击时钟的连接；额外攻击词条由攻击组件独立合成。
func ready_norm_signal_connect():
	super()
	signal_update_speed.connect(attack_component.owner_update_speed)

## [param enabled] 选择持续喷雾所有权；[param active] 表示当前是否允许实际喷射。
## 只改原生粒子，不按半秒重新触发长射击动画。
func set_continuous_fume(enabled: bool, active: bool = false) -> void:
	_continuous_fume = enabled
	_set_emitting(enabled and active)

## 原生射击动画的开始轨道；持续模式由攻击状态控制，忽略迟到的动画回调。
func _start_shoot():
	if not _continuous_fume:
		_set_emitting(attack_component.is_enabling and attack_component.is_attack_res and not is_death)

## 原生射击动画的结束轨道，不结束仍在运行的持续喷雾。
func _end_shoot():
	if not _continuous_fume:
		_set_emitting(false)

## 为全部原生粒子设置 [param emitting]；幂等更新不会重新启动同一状态。
func _set_emitting(emitting: bool) -> void:
	for particles: GPUParticles2D in all_bullet_fx: # 保留原粒子的自身生命周期和尾迹。
		if is_instance_valid(particles) and particles.emitting != emitting:
			particles.emitting = emitting
