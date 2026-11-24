extends BombEffectBase
class_name BombEffectDoom

@onready var animation_player: AnimationPlayer = $AnimationPlayer

## 播放毁灭菇闪光和爆炸动画。
func _play_effect() -> void:
	EventBus.push_event("canvas_layer_effect_once", [CanvasLayerEffect.E_CanvasLayerEffectType.Doom])

	animation_player.play("idle")
	await animation_player.animation_finished
	queue_free()
