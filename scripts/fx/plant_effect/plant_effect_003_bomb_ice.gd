extends BombEffectBase
class_name BombEffectIce

@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

## 释放冰雾并播放全屏冻结提示。
func _play_effect() -> void:
	EventBus.push_event("canvas_layer_effect_once", [CanvasLayerEffect.E_CanvasLayerEffectType.Ice])

	gpu_particles_2d.emitting = true
	await gpu_particles_2d.finished
	queue_free()
