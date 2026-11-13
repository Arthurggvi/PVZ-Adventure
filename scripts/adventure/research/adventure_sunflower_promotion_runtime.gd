## Adventure-only sunflower promotion runtime. Owns live placement-based effects;
## permanent skill choices still come solely from frozen PlantSpawnProfile records.
extends Node
class_name AdventureSunflowerPromotionRuntime

const SUNFLOWER := 2
const RESONANCE := "promotion_sunflower_resonance"
const HOLY_WAR := "promotion_sunflower_holy_war"
const FLOWER_FIELD := "promotion_sunflower_flower_field"
const DISCOUNT_STEP := 25
const AURA_DAMAGE_BONUS := 1.0
const AURA_DAMAGE_REDUCTION := 0.5

var game: MainGameManager
var _slots: CardSlotBattle
var _affected: Dictionary[int, Plant000Base] = {}
var _refresh_pending := false

func setup(owner_game: MainGameManager) -> void:
	game = owner_game

func _ready() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.card_manager):
		return
	_slots = game.card_manager.card_slot_battle
	if _slots != null:
		_slots.signal_card_committed.connect(_on_card_committed)
	for row: Array in game.plant_cell_manager.all_plant_cells:
		for cell: PlantCell in row:
			cell.signal_plant_create.connect(_on_board_changed.unbind(2))
			cell.signal_plant_free.connect(_on_board_changed.unbind(2))
	_refresh_blessings()

func _skill(card: Card, tier: int) -> String:
	if card == null or card.plant_spawn_profile == null:
		return ""
	var snapshot: Dictionary = card.battle_card_data
	if int(snapshot.get("plant_type", 0)) != SUNFLOWER:
		return ""
	return str(snapshot.get("promotion_%d" % tier, ""))

## The owned tier-four book empowers every sunflower planted from the deck.
func _has_flower_field_in_deck() -> bool:
	for planted_card: Card in _slots.curr_cards:
		if _skill(planted_card, 4) == FLOWER_FIELD:
			return true
	return false

func _on_card_committed(card: Card, consumed_free: bool) -> void:
	if card == null or card.card_reference == null:
		return
	if card.card_reference.card_type != ResourceCardReference.CardType.Plant:
		return
	if card.card_reference.content_id == SUNFLOWER and _has_flower_field_in_deck():
		for other: Card in _slots.curr_cards:
			if other.card_reference != null and other.card_reference.card_type == ResourceCardReference.CardType.Plant \
					and other.card_reference.content_id != SUNFLOWER:
				other.add_flower_field_discount(DISCOUNT_STEP)
				other.judge_sun_enough(_slots.sun_value)
	if _skill(card, 3) == RESONANCE and not consumed_free:
		card.set_card_cool_end()
		card.arm_resonance_next_free()
		card.judge_sun_enough(_slots.sun_value)
	# 阳光菇沿用同一次成功结算；续种标记和减免由实际出战卡持有。
	AdventureSunShroomCardEffects.on_card_committed(card, consumed_free, _slots)

func _on_board_changed() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	_refresh_blessings.call_deferred()

func _is_holy_war_source(plant: Plant000Base) -> bool:
	return _active(plant) and int(plant.plant_type) == SUNFLOWER \
		and plant.plant_spawn_profile != null \
		and str(plant.plant_spawn_profile.snapshot().get("promotion_4", "")) == HOLY_WAR

func _active(plant: Plant000Base) -> bool:
	return is_instance_valid(plant) and not plant.is_queued_for_deletion() and not plant.is_death

func _refresh_blessings() -> void:
	_refresh_pending = false
	if not is_instance_valid(game):
		return
	var next: Dictionary[int, Plant000Base] = {} # 本轮受影响的实际植物。
	for source_cell: PlantCell in game.board.cells(): # 每个真实种植点检查圣战来源。
		var has_source: bool = false # 本格多层植物只贡献一次来源。
		for candidate: Variant in source_cell.plant_in_cell.values(): # 当前实际占用。
			if _is_holy_war_source(candidate as Plant000Base):
				has_source = true
				break
		if not has_source:
			continue
		for target_cell: PlantCell in game.board.horizontal_neighbors(source_cell): # 前后拓扑邻格。
			for candidate: Variant in target_cell.living_plants(): # 普通与伴生活株均受益，多格植物按实例去重。
				var plant: Plant000Base = candidate as Plant000Base # 当前候选。
				if _active(plant):
					next[plant.get_instance_id()] = plant
	for id: int in _affected:
		if not next.has(id):
			_set_blessing(_affected[id], false)
	for id: int in next:
		_set_blessing(next[id], true)
	_affected = next

func _set_blessing(plant: Plant000Base, enabled: bool) -> void:
	if not is_instance_valid(plant):
		return
	plant.set_battle_aura_damage_bonus(AURA_DAMAGE_BONUS if enabled else 0.0)
	if is_instance_valid(plant.hp_component):
		plant.hp_component.damage_reduction.set_source(
			get_instance_id(), AURA_DAMAGE_REDUCTION if enabled else 0.0)

func _exit_tree() -> void:
	for plant: Plant000Base in _affected.values():
		_set_blessing(plant, false)
	_affected.clear()
