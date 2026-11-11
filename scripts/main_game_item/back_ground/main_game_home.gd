extends Node2D
class_name MainGameHome

@onready var area_2d_home: Area2D = $Area2DHome

@onready var door_downs: Array[Sprite2D] = [
	$Door/DoorDown/Background1GameoverInteriorOverlay,
	$Door/DoorDown/Background2GameoverInteriorOverlay,
	$Door/DoorDown/Background3GameoverInteriorOverlay,
	$Door/DoorDown/Background4GameoverInteriorOverlay,
	null,
	null
]

@onready var door_masks: Array[Sprite2D] = [
	$Door/DoorMask/Background1GameoverMask,
	$Door/DoorMask/Background2GameoverMask,
	$Door/DoorMask/Background3GameoverMask,
	$Door/DoorMask/Background4GameoverMask,
	$Door/DoorMask/Background5GameoverMask,
	$Door/DoorMask/Background6GameoverMask
]

## 刷新房门贴图，保留进门检测和失败演出所需的节点。
## [param game_BG] 原版背景枚举，用于选择对应的房门和遮罩。
## [param use_original_door] 仅在使用原版背景时显示与之配套的贴图。
func init_home(game_BG: ConstLevelData.GameBg, use_original_door: bool = true) -> void:
	for background_index in door_masks.size(): # 遍历原版背景对应的每组贴图。
		var show_door := use_original_door and background_index == game_BG # 当前贴图组是否与战场背景配套。
		if is_instance_valid(door_downs[background_index]):
			door_downs[background_index].visible = show_door
		door_masks[background_index].visible = show_door

## 僵尸进房
func _on_area_2d_home_area_entered(area: Area2D) -> void:
	print("僵尸进家")
	var zombie :Zombie000Base = area.owner
	EventBus.push_event("zombie_go_home", [zombie])

## 僵尸无法进房，禁用房子
func disable_home():
	area_2d_home.monitoring = false
