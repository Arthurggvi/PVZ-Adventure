## 水路清洁车，水陆动画由共用水体探测器驱动。
extends LawnMover
class_name PoolCleaner

## 启动时记录的正常移速，吸入僵尸结束后恢复。
var ori_move_speed:float

#region 游泳相关

## 是否正在吸入僵尸，供动画树选择吸入姿态。
var is_zombie: bool = false

@export_group("游泳相关")
## 动画树使用的水中状态，由聚合后的水体接触更新。
@export var is_water := false
#endregion


func _ready() -> void:
	super._ready()
	ori_move_speed = move_speed
	(area_2d as WaterContactArea).water_contact_changed.connect(_on_water_contact_changed)

## 启动小推车
func _start_mower():
	if is_destroyed or is_queued_for_deletion():
		return
	is_moving = true
	SoundManager.play_other_SFX("pool_cleaner")
	animation_player.play("PoolCleaner_land")
	_mower_run_all_zombie_on_start()

func suck_end():
	if is_destroyed or is_queued_for_deletion():
		return
	move_speed = ori_move_speed
	is_zombie = false

## 小推车碾压一个僵尸
func _mower_run_one_zombie(zombie :Zombie000Base):
	if is_destroyed or is_queued_for_deletion() or not is_instance_valid(zombie) or zombie.is_queued_for_deletion():
		return
	zombie.character_death_disappear()
	move_speed = ori_move_speed / 4
	is_zombie = true

## 根据 [param touching] 切换水陆动画，并在切换处播放一次水花。
func _on_water_contact_changed(touching: bool) -> void:
	if is_destroyed or is_queued_for_deletion():
		return
	is_water = touching
	var splash := SceneRegistry.SPLASH.instantiate() as Splash # 与推车同级的水花。
	splash.position = position
	get_parent().add_child.call_deferred(splash)
