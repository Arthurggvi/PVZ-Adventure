extends BombEffectBase
class_name BombEffectPotatoMine

## 向上抛散的土豆碎屑，由场景配置一次性爆发。
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D
## 爆炸瞬间的闪光。
@onready var flash: Sprite2D = $Flash
## 爆炸字样，先弹出再淡去。
@onready var spudow: Sprite2D = $Spudow

## 爆炸表现脱离植物后播放，淡出结束时一并清理残渣和粒子。
func activate_bomb_effect() -> void:
	super()
	gpu_particles_2d.emitting = true
	EventBus.push_event(MainGameCamera.SHAKE_EVENT, [Vector2(3, 4), 0.16])

	# 补间与粒子并行，爆炸字样在碎屑消失后短暂停留。
	var impact_tween: Tween = create_tween().set_parallel()
	impact_tween.tween_property(flash, ^"modulate:a", 0.0, 0.12)
	impact_tween.tween_property(spudow, ^"scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	impact_tween.tween_property(spudow, ^"modulate:a", 0.0, 0.28).set_delay(0.30)
	await impact_tween.finished
	queue_free()
