## 豌豆协同的棋盘与卡牌派生属性：只读取当前已种植的真实实例。
extends Node
class_name AdventurePeaSynergyRuntime

## 同种豌豆射手的注册物种编号。
const PEA := 1
## 二转协同书的稳定标识。
const SYNERGY := "promotion_peashooter_synergy"
## 互不覆盖其他增伤光环的专用来源。
const AURA_KEY: StringName = &"peashooter_synergy"
## 由关卡运行时注入的战斗场景。
var game: MainGameManager
## 上一轮受光环影响的植物弱引用，撤销时不持有已销毁实例。
var _affected: Dictionary[int, WeakRef] = {}
## 一帧内多个种植/死亡事件只触发一次全盘重算。
var _pending: bool = false

## [param battle] 当前关卡游戏管理器，须在加入场景树前配置。
func setup(battle: MainGameManager) -> void:
	game = battle

func _ready() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.plant_cell_manager):
		return
	game.board.plant_relocated.connect(_on_board_change)
	for row: Array in game.plant_cell_manager.all_plant_cells:
		for cell: PlantCell in row:
			cell.signal_plant_create.connect(_on_board_change.unbind(2))
			cell.signal_plant_free.connect(_on_board_change.unbind(2))
	_refresh()

func _on_board_change() -> void:
	if _pending:
		return
	_pending = true
	_refresh.call_deferred()

## 存活豌豆射手按实例去重，相邻双方至少一人携带协同才计一条关系。
func _refresh() -> void:
	_pending = false
	if not is_instance_valid(game) or not is_instance_valid(game.plant_cell_manager):
		return
	var plants: Dictionary[int, Plant000Base] = {}
	var sources: Dictionary[int, bool] = {}
	for row: Array in game.plant_cell_manager.all_plant_cells:
		for cell: PlantCell in row:
			for entry: Variant in cell.plant_in_cell.values():
				var plant: Plant000Base = entry as Plant000Base
				if not _active(plant) or int(plant.plant_type) != PEA:
					continue
				var id: int = plant.get_instance_id()
				if plants.has(id):
					continue
				plants[id] = plant
				var snapshot: Dictionary = plant.plant_spawn_profile.snapshot() if plant.plant_spawn_profile != null else {}
				sources[id] = str(snapshot.get("promotion_2", "")) == SYNERGY
	var buffs: Dictionary[int, float] = {}
	var ids: Array = plants.keys()
	for i: int in range(ids.size()):
		var left: Plant000Base = plants[ids[i]]
		for j: int in range(i + 1, ids.size()):
			var right: Plant000Base = plants[ids[j]]
			if not (sources[ids[i]] or sources[ids[j]]):
				continue
			if not game.board.neighbors(left.plant_cell).has(right.plant_cell):
				continue
			buffs[ids[i]] = float(buffs.get(ids[i], 0.0)) + 0.1
			buffs[ids[j]] = float(buffs.get(ids[j], 0.0)) + 0.1
	for id: int in _affected:
		if buffs.has(id):
			continue
		var former: Plant000Base = _affected[id].get_ref() as Plant000Base
		if is_instance_valid(former):
			former.set_battle_aura_damage_source(AURA_KEY, 0.0)
	_affected.clear()
	for id: int in buffs:
		var plant: Plant000Base = plants[id]
		plant.set_battle_aura_damage_source(AURA_KEY, buffs[id])
		_affected[id] = weakref(plant)
	_refresh_cards(plants.size())

## 本卡的价格和下一次冷却按场上同种总数修正，最多叠加五层。
func _refresh_cards(plant_count: int) -> void:
	if not is_instance_valid(game.card_manager):
		return
	var slots: CardSlotBattle = game.card_manager.card_slot_battle
	if not is_instance_valid(slots):
		return
	for card: Card in slots.curr_cards:
		if card == null or int(card.battle_card_data.get("plant_type", 0)) != PEA:
			continue
		var enabled: bool = str(card.battle_card_data.get("promotion_2", "")) == SYNERGY
		card.set_pea_synergy_count(plant_count if enabled else 0)

## 只有仍属于本场景且存活的植物参与邻接与数量计算。
func _active(plant: Plant000Base) -> bool:
	return is_instance_valid(plant) and not plant.is_queued_for_deletion() and not plant.is_death

func _exit_tree() -> void:
	for id: int in _affected:
		var plant: Plant000Base = _affected[id].get_ref() as Plant000Base
		if is_instance_valid(plant):
			plant.set_battle_aura_damage_source(AURA_KEY, 0.0)
	_affected.clear()
	if is_instance_valid(game) and is_instance_valid(game.card_manager):
		var slots: CardSlotBattle = game.card_manager.card_slot_battle
		if is_instance_valid(slots):
			for card: Card in slots.curr_cards:
				if is_instance_valid(card):
					card.set_pea_synergy_count(0)
