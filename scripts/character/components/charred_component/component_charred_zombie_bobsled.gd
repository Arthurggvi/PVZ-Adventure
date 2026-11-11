extends CharredComponent
class_name CharredComponentZombieBobsled

## 原车的后板和前板，灰烬按相同位置使用黑色剪影。
@onready var sled_panels: Array[Sprite2D] = [$"../ZombieBobsledInside", $"../ZombieBobsled1"]

## 灰烬动画
@onready var zombie_charred: Array[Node2D] = [
	%ZombieCharred, %ZombieCharred2, %ZombieCharred3, %ZombieCharred4
]
@onready var all_anim_lib: Array[AnimationPlayer] = [
	$ZombieCharred/CharredCorrect/AnimLib,
	$ZombieCharred2/CharredCorrect/AnimLib,
	$ZombieCharred3/CharredCorrect/AnimLib,
	$ZombieCharred4/CharredCorrect/AnimLib,
]

## 播放灰烬动画
func play_charred_anim():
	super()
	# i 是雪橇图层索引，后板插在四名队员的剪影之后。
	for i in range(sled_panels.size()):
		# panel 复制雪橇的当前损坏纹理、位置和缩放。
		var panel: Sprite2D = sled_panels[i].duplicate() as Sprite2D
		add_child(panel)
		panel.global_transform = sled_panels[i].global_transform
		panel.modulate = Color.BLACK
		if i == 0:
			move_child(panel, 0)
	for i in range(4):
		zombie_charred[i].visible = true
		all_anim_lib[i].play("ALL_ANIMS")
	await all_anim_lib[0].animation_finished
	queue_free()
