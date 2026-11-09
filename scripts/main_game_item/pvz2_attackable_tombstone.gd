extends TombStone
class_name PvZ2AttackableTombstone

## Original PvZ2 Dark Ages gravestone: 700 HP and damage thresholds.
const MAX_HEALTH := 700
const DAMAGE_THRESHOLDS := [1, 150, 300, 450]
const DAMAGE_ART: Array[Texture2D] = [
	preload("res://assets/adventure/structures/pvz2_tombstone_dark/intact.png"),
	preload("res://assets/adventure/structures/pvz2_tombstone_dark/damage_1.png"),
	preload("res://assets/adventure/structures/pvz2_tombstone_dark/damage_2.png"),
	preload("res://assets/adventure/structures/pvz2_tombstone_dark/damage_3.png"),
	preload("res://assets/adventure/structures/pvz2_tombstone_dark/damage_4.png"),
]
@onready var damage_receiver: PvZ2TombstoneTarget = $DamageReceiver

func _enter_tree() -> void:
	($DamageReceiver as Character000Base).lane = row_col.x

func _ready() -> void:
	super._ready()
	damage_receiver.health_changed.connect(update_damage_visual)
	damage_receiver.destroyed.connect(tombstone_death)

func _init_random_frame() -> void:
	tombstone.hframes = 1
	tombstone.vframes = 1
	tombstone.frame = 0
	tombstone.texture = DAMAGE_ART[0]
	mound.frame = randi_range(0, 4)
	SoundManager.play_other_SFX("gravestone_rumble")

func update_damage_visual(current_hp: int) -> void:
	var damage := MAX_HEALTH - clampi(current_hp, 0, MAX_HEALTH)
	var state := 0
	for threshold in DAMAGE_THRESHOLDS:
		if damage >= threshold:
			state += 1
	var art := DAMAGE_ART[state]
	if tombstone.texture == art:
		return
	tombstone.texture = art
	# Maintain the bottom anchor as the original cracks change the sprite size.
	tombstone.position.y = 106.0 - float(art.get_height()) * 0.5

func get_tombstone_kind() -> StringName:
	return &"pvz2"

func get_current_hp() -> int:
	return damage_receiver.hp_component.curr_hp

func restore_hp(saved_hp: int) -> void:
	var hp := clampi(saved_hp, 1, MAX_HEALTH)
	damage_receiver.hp_component.curr_hp = hp
	update_damage_visual(hp)
