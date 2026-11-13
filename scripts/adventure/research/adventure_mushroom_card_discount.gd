## 单株蘑菇到真实来源卡的临时减费链接；弱持有双方，不修改冻结配方或永久卡资料。
extends RefCounted
class_name AdventureMushroomCardDiscount

## 共生减费的独立家族；Card 在家族内取最大值，不随受益株数或来源数累加。
const FAMILY: StringName = &"scaredy_symbiosis"
## 持续费用减免的阳光数，仅在至少一个有效受益者仍存在时应用。
const DISCOUNT: int = 25
## 受益植株弱引用；无来源卡的场景植物仍可拥有其他共享效果。
var _plant: WeakRef
## 首次有效绑定的战场弱引用，拒绝跨场景借用同 UID 卡。
var _game: WeakRef
## 已登记费用贡献的真实卡实例弱引用，用于换卡和退出时对称撤销。
var _card: WeakRef
## 目标控制器的稳定来源 ID，允许同 UID 的多株分别登记并独立退出。
var _source_id: int = 0
## 最近一次合成输出；延迟刷新只读取最后状态，合并同帧多次变化。
var _enabled: bool = false
## 每帧最多排队一个刷新任务；重复启用仍允许未来重新查找替换后的实卡。
var _pending: bool = false

## [param plant] 为受益实体；[param source_id] 是其控制器的正实例 ID。
## 重新配置先撤销旧贡献；尚未入树时暂不绑定战场，首次刷新再校验。
func configure(plant: Plant000Base, source_id: int) -> void:
	clear()
	_plant = weakref(plant) if is_instance_valid(plant) else null
	_source_id = source_id
	_game = null

## [param enabled] 是本轮是否拥有费用词条；延迟到本次种植扣费结束后刷新。
## 重复 true 不重复排队，但会在以后刷新时重查 UID 实卡，支持卡片被替换。
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if _pending:
		return
	_pending = true
	_flush.call_deferred()

## 立即撤销本实例在旧卡上的贡献；保留已排队任务，由最终禁用状态阻止重新授予。
func clear() -> void:
	_enabled = false
	_release_card()

## 同帧只提交最后状态；成功种植不会把本次确认价格改成新植株入圈后的价格。
func _flush() -> void:
	_pending = false
	var next_card: Card = _find_card() if _enabled else null # 仅真实有效目标可以提供临时费用来源。
	var old_card: Card = _card.get_ref() as Card if _card != null else null # 弱引用允许旧卡已被释放。
	if old_card != next_card:
		_release_card()
		_card = weakref(next_card) if is_instance_valid(next_card) else null
	if is_instance_valid(next_card):
		next_card.set_battle_discount_source(FAMILY, _source_id, DISCOUNT)

## 查找当前战场、当前 UID 的实际出战卡；无配方、非冒险或无实卡时返回 null。
func _find_card() -> Card:
	var plant: Plant000Base = _plant.get_ref() as Plant000Base if _plant != null else null # 受益实体可先于延迟任务离场。
	var game: MainGameManager = _game.get_ref() as MainGameManager if _game != null else Global.main_game # 首次刷新才冻结战场。
	if not MushroomPlantQuery.is_active(plant, game) or _source_id <= 0 \
			or not AdventureSession.owns_battle(game.game_para) or plant.plant_spawn_profile == null \
			or not is_instance_valid(game.card_manager):
		return null
	if _game == null:
		_game = weakref(game)
	var snapshot: Dictionary = plant.plant_spawn_profile.snapshot() # 只读冻结 UID，绝不按物种代领其他卡收益。
	var uid: String = str(snapshot.get("uid", "")) # 空 UID 不构造卡片或临时资料。
	var slots: CardSlotBattle = game.card_manager.card_slot_battle # 仅使用当前真实普通出战卡槽。
	if uid.is_empty() or not is_instance_valid(slots):
		return null
	var card: Card = slots.find_plant_card_by_uid(uid) # 没有该 UID 的实卡时费用词条自然无目标。
	if not is_instance_valid(card) or card.is_queued_for_deletion() or not card.is_node_ready() \
			or not slots.curr_cards.has(card) or card.card_context != Card.CardContext.Battle \
			or card.card_reference == null or card.card_reference.card_type != ResourceCardReference.CardType.Plant:
		return null
	return card

## 只撤销本目标 ID 的家族来源；同 UID 的其他受益植物继续保留同一份减免。
func _release_card() -> void:
	var card: Card = _card.get_ref() as Card if _card != null else null # 旧卡可能已随场景释放。
	_card = null
	if is_instance_valid(card):
		card.set_battle_discount_source(FAMILY, _source_id, 0)
