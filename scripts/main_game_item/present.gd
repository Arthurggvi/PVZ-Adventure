extends Node2D
class_name Present
## 掉落的植物
@onready var pick_up_glow: Sprite2D = $PickUpGlow

@onready var present: Sprite2D = $Present
@onready var present_open: Sprite2D = $PresentOpen
@onready var texture_button: TextureButton = $TextureButton
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

func _ready():
	var tween = create_tween()
	tween.tween_property(pick_up_glow, "scale", Vector2(1.5, 1.5), 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(pick_up_glow, "scale", Vector2(1, 1), 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.set_loops()  # 无限循环

	if BattleCollectionPolicy.allows(false):
		collect()

	## 等待10秒未点击删除
	await get_tree().create_timer(10.0).timeout
	queue_free()


## 拾取礼盒并登记花园植物，点击和自动拾取共用一次入账。
func collect() -> void:
	if not texture_button.visible:
		return
	SoundManager.play_other_SFX("prize")

	var reminder_info :ReminderInformation =  SceneRegistry.REMINDER_INFORMATION.instantiate()
	get_tree().current_scene.add_child(reminder_info)
	reminder_info._init_info(["你为你的花园找到一株新植物"], 2)

	texture_button.visible = false
	present_open.visible = true
	Global.global_game_state.curr_num_new_garden_plant += 1
	gpu_particles_2d.emitting = true

	Global.save_service.save_now()

	await gpu_particles_2d.finished
	queue_free()

