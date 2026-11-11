extends Node2D
class_name  TombStone

@onready var tombstone: Sprite2D = $TombstoneMask/tombstone
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D
@onready var mound: Sprite2D = $MoundMask/mound
@onready var tombstone_mask: Panel = $TombstoneMask

@export var zombie_candidate_list :Array[CharacterRegistry.ZombieType]

var plant_cell:PlantCell
var new_zombie:Zombie000Base
var row_col:Vector2i

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_init_tombstone()

## 初始化赋值
func init_tombstone(curr_plant_cell:PlantCell):
	self.plant_cell = curr_plant_cell
	self.row_col = plant_cell.row_col

## 随机生成一种墓碑（一共5种）
func _init_random_frame():
	var random_frame = randi_range(0,4)
	tombstone.frame = random_frame
	mound.frame = random_frame
	SoundManager.play_other_SFX("gravestone_rumble")

## 初始化墓碑
func _init_tombstone():
	_init_random_frame()
	gpu_particles_2d.emitting = true
	var mound_ori_position = mound.position
	var tombstone_ori_position = tombstone.position
	mound.position = Vector2(39, 84)
	tombstone.position = Vector2(39, 136)
	await get_tree().create_timer(0.5).timeout
	var tween := create_tween()
	tween.tween_property(mound, "position", mound_ori_position, 0.1)
	tween.tween_property(tombstone, "position", tombstone_ori_position, 0.5)


## 被墓碑吞吃时修改mask位置
func start_be_grave_buster_eat():
	tombstone_mask.position.y += 30
	tombstone.position.y -= 30

func failure_eat_tombstone():
	tombstone_mask.position.y -= 30
	tombstone.position.y += 30

## Unified grave-cell spawn. Neither the tombstone nor the normal flag-wave
## rules schedule revivals: callers opt in explicitly (e.g. White Duke).
## Only this endpoint assigns grave coordinates and plays the original emerge animation.
func spawn_from_grave(zombie_type: CharacterRegistry.ZombieType,
		modifier: ZombieSpawnModifier = null, health_ratio: float = 1.0,
		on_created: Callable = Callable(), natural: bool = true,
		anim_multiply: float = 1.0) -> Zombie000Base:
	if not is_inside_tree() or is_queued_for_deletion() or is_instance_valid(new_zombie) \
			or not is_instance_valid(plant_cell) or health_ratio <= 0.0:
		return null
	var game: MainGameManager = Global.main_game
	if not is_instance_valid(game) or not game.is_ancestor_of(self) \
			or not game.zombie_manager.is_game_running():
		return null
	var manager: ZombieManager = game.zombie_manager
	var lane: int = row_col.x
	if not manager.can_spawn_zombie_in_lane(zombie_type, lane):
		return null
	var zombie_init_para: Dictionary = {
		Zombie000Base.E_ZInitAttr.CharacterInitType: Character000Base.E_CharacterInitType.IsNorm,
		Zombie000Base.E_ZInitAttr.Lane: lane,
		Zombie000Base.E_ZInitAttr.CurrWave: -1,
		Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: natural,
	}
	var row: ZombieRow = manager.all_zombie_rows[lane]
	var position_at_grave := Vector2(global_position.x,
			row.zombie_create_position.global_position.y)
	var zombie: Zombie000Base = manager.create_norm_zombie(zombie_type, row,
		zombie_init_para, position_at_grave, Callable(), modifier)
	if not is_instance_valid(zombie):
		return null
	new_zombie = zombie
	if health_ratio < 1.0:
		var hp: HpComponentZombie = zombie.hp_component as HpComponentZombie
		hp.curr_hp = maxi(1, ceili(hp.max_hp * health_ratio))
		if hp.max_hp_armor1 > 0:
			hp.curr_hp_armor1 = maxi(1, ceili(hp.max_hp_armor1 * health_ratio))
		if hp.max_hp_armor2 > 0:
			hp.curr_hp_armor2 = maxi(1, ceili(hp.max_hp_armor2 * health_ratio))
	zombie.tree_exiting.connect(_forget_emerging.bind(weakref(zombie)), CONNECT_ONE_SHOT)
	if on_created.is_valid():
		on_created.call(zombie)
	# 白爵士在场时，所有墓碑出土都继承复生外观，包括旗帜波触发的出土。
	for boss: ZB000Base in manager.get_living_bosses():
		if boss is ZB003WhiteDuke:
			zombie.body.start_white_flame_revival()
			break
	_emerge_zombie(zombie, anim_multiply)
	return zombie

## Compatibility with flag waves / old grave event consumers; same emergence path.
func create_new_zombie(zombie_type: CharacterRegistry.ZombieType,
		anim_multiply: float = 1.0) -> void:
	spawn_from_grave(zombie_type, null, 1.0, Callable(), true, anim_multiply)

func _emerge_zombie(zombie: Zombie000Base, anim_multiply: float) -> void:
	await zombie.zombie_up_from_tombstone(maxf(0.01, anim_multiply))
	_forget_emerging(weakref(zombie))

func _forget_emerging(reference: WeakRef) -> void:
	if new_zombie == reference.get_ref():
		new_zombie = null

## 墓碑存档协议。派生类覆盖种类、血量和恢复，旧墓碑保持无血量语义。
func get_tombstone_kind() -> StringName:
	return &"legacy"

func get_current_hp() -> int:
	return 0

func restore_hp(_hp: int) -> void:
	pass

## 墓碑死亡
func tombstone_death():
	plant_cell.tombstone.plant_cell.tombstone_death_update_plant_cell_data()
	queue_free()
