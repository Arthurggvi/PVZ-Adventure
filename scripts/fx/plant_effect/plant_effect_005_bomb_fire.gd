extends BombEffectBase
class_name BombEffectFire

@onready var animation_player: AnimationPlayer = $AnimationPlayer
var exist_time := 1.0

func set_exist_time(new_exist_time:float = 1.0):
	self.exist_time = new_exist_time

## 播放火焰并在持续时间结束后淡出。
func _play_effect() -> void:
	animation_player.play("fire_flame")
	await get_tree().create_timer(exist_time + randf() / 5).timeout
	animation_player.play("fire_done")

func _fire_end():
	queue_free()
