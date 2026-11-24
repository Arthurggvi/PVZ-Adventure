extends Node
class_name DIM_Coin
## 掉落管理器的子节点，掉落金币使用


## 要求必须有这个金币显示label
@onready var coin_bank_label: CoinBankLabel = %CoinBankLabel
## 掉落金币的父节点
@export var all_drop_coin_parent: Node2D

func _ready() -> void:
	EventBus.subscribe("create_coin", create_coin)

## 按 [param probability] 抽选银币、金币或钻石，合计概率必须为 1。
## [param global_position_new_coin] 是世界坐标，[param target_position] 是相对落点偏移。
func create_coin(probability:Array=[0.5, 0.5, 0], global_position_new_coin:Vector2=Vector2.ZERO, target_position:Vector2=Vector2(randf_range(-50, 50), randf_range(80, 90))):
	var probability_sum: float = float(probability[0]) + float(probability[1]) + float(probability[2]) # 检查三个互斥面额的概率合计。
	assert(abs(probability_sum - 1.0) < 0.001, "概率和不为1")
	var roll: float = randf() # 单次随机值决定面额。
	var scene: PackedScene # 惰性加载本次实际掉落的面额场景。
	if roll < probability[0]:
		scene = SceneRegistry.COIN_SILVER
	elif roll < probability[0] + probability[1]:
		scene = SceneRegistry.COIN_GOLD
	else:
		scene = SceneRegistry.COIN_DIAMOND
	spawn_coin(scene, global_position_new_coin, target_position)

## 从面额 [param scene] 生成一枚钱币，从 [param origin] 世界坐标抛向局部 [param landing_offset]。
## [param persistent] 为真时保留至拾取或离场，面额仍享受既有战场金币倍率。
func spawn_coin(scene: PackedScene, origin: Vector2, landing_offset: Vector2, persistent: bool = false) -> void:
	if not is_instance_valid(coin_bank_label) or not is_instance_valid(all_drop_coin_parent) or scene == null:
		return
	coin_bank_label.update_label()
	var new_coin: Coin = scene.instantiate() # 同一套入账、金币倍率和抛物线供保底与普通掉落使用。
	if is_instance_valid(Global.main_game) and Global.main_game.is_ancestor_of(self):
		var effects: PlayerEffects = AdventureSession.player_effects_for(Global.main_game.game_para) # 原版得到中性倍率，花园不受冒险徽章影响。
		var amount: int = PlayerEffects.scale_amount(new_coin.coin_value, effects.coin_multiplier) # 生成时固定金额，拾取不再乘算。
		if amount < 1:
			new_coin.free()
			return
		new_coin.coin_value = amount
	if persistent:
		new_coin.exist_time = 0.0
	all_drop_coin_parent.add_child(new_coin)
	new_coin.setup(coin_bank_label.marker_2d_coin_target)
	new_coin.global_position = origin
	new_coin.launch(landing_offset)
