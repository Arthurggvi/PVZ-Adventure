## 本局出战卡冷却效果所有者：只改当前卡槽的临时倍率，不写卡牌数据库。
extends Node
class_name AdventureCardCooldownRuntime

var zombies: ZombieManager
var _elapsed := 0.0
var _effects: Dictionary[StringName, Dictionary] = {}

func setup(manager: ZombieManager) -> void:
	zombies = manager
	set_process(false)

func apply(event: StageEventDefinition) -> void:
	if not is_instance_valid(zombies):
		return
	if event.cooldown_operation == StageEventDefinition.CooldownOperation.ADJUST_REMAINING_SECONDS:
		for card: Card in _cards():
			if _matches(card, event.cooldown_scope, event.cooldown_plant_type):
				card.adventure_adjust_remaining_cooldown(event.cooldown_value)
		return
	_effects[event.event_id] = {"end": _elapsed + event.cooldown_duration_seconds,
		"factor": event.cooldown_value, "scope": event.cooldown_scope, "plant_type": event.cooldown_plant_type}
	_refresh_cards()
	set_process(true)

func _process(delta: float) -> void:
	if not zombies.is_game_running():
		return
	_elapsed += delta
	var changed := false
	for id: StringName in _effects.keys():
		if _elapsed >= float(_effects[id]["end"]):
			_effects.erase(id)
			changed = true
	if changed:
		_refresh_cards()
	if _effects.is_empty():
		set_process(false)

func clear() -> void:
	_effects.clear()
	set_process(false)
	_refresh_cards()

func _cards() -> Array[Card]:
	if not is_instance_valid(zombies) or not is_instance_valid(zombies.main_game):
		var empty: Array[Card] = []
		return empty
	return zombies.main_game.card_manager.card_slot_battle.curr_cards

func _matches(card: Card, scope: int, plant_type: int) -> bool:
	return scope == StageEventDefinition.CooldownScope.ALL_SELECTED or \
		(scope == StageEventDefinition.CooldownScope.PLANT_TYPE and
			card.card_reference.content_id == plant_type)

func _refresh_cards() -> void:
	for card: Card in _cards():
		var multiplier := 1.0
		for effect: Dictionary in _effects.values():
			if _matches(card, effect["scope"], effect["plant_type"]):
				multiplier *= float(effect["factor"])
		card.adventure_cooldown_multiplier = clampf(multiplier, 0.05, 20.0)

func _exit_tree() -> void:
	clear()
