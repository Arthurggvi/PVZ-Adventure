extends BombEffectBase
class_name BombEffectCobCannon
## 加农炮子弹爆炸特效

@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

## 发射玉米炮落地粒子并在结束后回收。
func _play_effect() -> void:
	gpu_particles_2d.emitting = true

	await gpu_particles_2d.finished
	queue_free()
