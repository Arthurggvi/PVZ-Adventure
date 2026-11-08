extends Node2D
class_name Ladder

const LADDER_SOURCE_TEXTURE := "res://assets/reanim/Zombie_ladder_5.png"

@onready var iron_node: IronNode = $IronNode
@onready var area_2d_detect: Area2D = $Area2DDetect

## 梯子所属植物格子
var plant_cell:PlantCell
## 梯子所在行
var lane:int

## Placed ladder keeps the tier of its owning zombie, including across save/load.
var adventure_tier_id: StringName = &""

func _ready() -> void:
	## 斜面时更新对应的检测位置
	GlobalUtils.update_plant_cell_slope_y(plant_cell, area_2d_detect)

## 初始化梯子
func init_ladder(curr_plant_cell:PlantCell, tier_id: StringName = &""):
	self.plant_cell = curr_plant_cell
	self.lane = plant_cell.row_col.x
	self.adventure_tier_id = tier_id
	if tier_id == &"" or tier_id == &"base":
		return
	# Use the same species-level art mapping as the zombie, not global texture mutation.
	var textures: Dictionary = AdventureZombieTierArtCatalog.textures_for(
			int(CharacterRegistry.ZombieType.Z022Ladder), tier_id)
	var replacement: Texture2D = textures.get(LADDER_SOURCE_TEXTURE) as Texture2D
	if replacement == null:
		return
	($ZombieLadder as Sprite2D).texture = replacement
	($IronNode/Zombie_ladder_1 as Sprite2D).texture = replacement

## 梯子死亡
func ladder_death():
	plant_cell.ladder_loss()
	queue_free()

func _on_area_2d_area_entered(area: Area2D) -> void:
	var zombie :Zombie000Base = area.owner
	if lane == zombie.lane and not zombie.is_ignore_ladder:
		zombie.start_climbing_ladder()
