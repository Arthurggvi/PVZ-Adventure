## 战场材料掉落挂载点：怪物死亡时按当前阶段的材料池尝试掉落一份材料。
## 同时负责单场战斗的拾取额度：已拾取数量达到上限后不再生成新的材料掉落。
extends Node
class_name DIM_BattleDrop

## 单场战斗允许拾取的材料掉落上限；达到后不再产生新的材料掉落。
@export var max_collected := 20

## 金币栏标签，材料拾取时飞向它的锚点。
@onready var coin_bank_label: CoinBankLabel = %CoinBankLabel
## 材料掉落物的父节点，通常与金币的 AllDropCoin 相同。
@export var all_drop_parent: Node2D

## 本场战斗已拾取的材料数量。
var _collected := 0
## 计数所属的阶段；阶段变化（普通转噩梦）时重新计数。
var _phase: StagePhaseDefinition

func _ready() -> void:
	EventBus.subscribe("create_material_drop", create_material_drop)

## 在 [param origin] 处尝试掉落一份材料；非冒险战斗、额度用尽或阶段未就绪时静默忽略。
func create_material_drop(origin: Vector2) -> void:
	var phase := AdventureSession.active_phase
	if phase == null or not is_instance_valid(all_drop_parent) or not is_instance_valid(Global.main_game) \
			or not AdventureSession.owns_battle(Global.main_game.game_para):
		return
	# 阶段对象变化即视为新的一场战斗，重新给满额度。
	if phase != _phase:
		_phase = phase
		_collected = 0
	if _collected >= max_collected:
		return
	var effects: PlayerEffects = AdventureSession.player_effects_for(Global.main_game.game_para) # 同一出战快照供场内和结算使用。
	var pickup := BattleDropService.drop_material(phase, all_drop_parent, coin_bank_label.marker_2d_coin_target, origin, effects)
	if pickup != null:
		pickup.collected.connect(_on_pickup_collected)

## 只有真正拾取入账的材料才消耗额度，未拾取而超时消失的不计入。
func _on_pickup_collected(_pickup: BattlePickup) -> void:
	_collected += 1
