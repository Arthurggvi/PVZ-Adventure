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
## Attackable ladder HP is independent of its carrier's helmet pool.
@export var max_hp := 1000
var current_hp := 1000
var nullified_plant: Plant000Base
var nullify_persistent := false
var _destroyed := false
signal destroyed

func _ready() -> void:
	## 斜面时更新对应的检测位置
	GlobalUtils.update_plant_cell_slope_y(plant_cell, area_2d_detect)

## 初始化梯子
func init_ladder(curr_plant_cell:PlantCell, tier_id: StringName = &"",
        target: Plant000Base = null):
	self.plant_cell = curr_plant_cell
	self.lane = plant_cell.row_col.x
	self.adventure_tier_id = tier_id
	# The placed ladder is an attackable combat item. Configure its collision
	# identity when bound to a cell so inherited/loaded scene defaults cannot
	# leave the hit region on the generic layer.
	var hit_area: Area2D = get_node("Area2DReal") as Area2D
	hit_area.collision_layer = (1 << 12) | (1 << 9)
	hit_area.collision_mask = 0
	var rules: Array[Dictionary] = AdventureZombieTierTraits.for_spawn(
			CharacterRegistry.ZombieType.Z022Ladder, tier_id)
	var policy: Dictionary = rules[0] if not rules.is_empty() else {}
	max_hp = int(policy.get("ladder_hp", 1000))
	current_hp = max_hp
	if bool(policy.get("nullify", false)):
		nullified_plant = target if is_instance_valid(target) else plant_cell.get_bungi_target()
		nullify_persistent = bool(policy.get("nullify_persistent", false))
		if is_instance_valid(nullified_plant):
			AdventurePlantNullification.grant(nullified_plant, get_instance_id())
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
func take_damage(damage: int) -> int:
	if _destroyed or damage <= 0:
		return 0
	var dealt: int = mini(damage, current_hp)
	current_hp -= dealt
	if current_hp <= 0:
		ladder_death()
	return dealt

func ladder_death():
	if _destroyed:
		return
	_destroyed = true
	_release_nullification()
	if is_instance_valid(plant_cell):
		plant_cell.ladder_loss(self)
	destroyed.emit()
	queue_free()

func _exit_tree() -> void:
	_release_nullification()

func _release_nullification() -> void:
	if is_instance_valid(nullified_plant):
		AdventurePlantNullification.release(
				nullified_plant, get_instance_id(), nullify_persistent)
	nullified_plant = null

func _on_area_2d_area_entered(area: Area2D) -> void:
	var zombie :Zombie000Base = area.owner
	if lane == zombie.lane and not zombie.is_ignore_ladder:
		zombie.start_climbing_ladder()
