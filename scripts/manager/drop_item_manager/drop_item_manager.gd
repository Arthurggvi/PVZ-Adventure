extends MainGameSubManager
class_name DropItemManager
## 掉落道具管理器, 管理掉落金币、花盆
## 主游戏场景和花园场景使用

## 首通钱币在落点最多排七列，让普通和噩梦的钱堆都能留在战场内。
const FIRST_CLEAR_COLUMNS := 7
## 首通收取的飞行时间（秒）；最长的普通与噩梦两堆也须在白屏结束前抵达。
const FIRST_CLEAR_FLIGHT_SECONDS := 0.26
## 首通同批两枚之间的启动间隔（秒）。
const FIRST_CLEAR_COIN_INTERVAL := 0.035
## 每批结束后额外留出的间隔（秒），使 1、2、3、4 枚的节奏可辨。
const FIRST_CLEAR_BATCH_GAP := 0.065

@onready var dim_garden_plant: DIM_GardenPlant = $DIM_GardenPlant
@onready var dim_coin: DIM_Coin = $DIM_Coin


func _ready() -> void:
	EventBus.subscribe("gold_magnet_attract_once", gold_magnet_attract_once)

func init_manager() -> void:
	pass

## 吸金磁把普通钱币吸向 [param target_pos]；首通钱堆留给玩家或奖杯拾取。
func gold_magnet_attract_once(target_pos: Vector2) -> void:
	for drop: Node in dim_coin.all_drop_coin_parent.get_children(): # 金币与材料共用掉落层。
		if drop is Coin and drop.first_clear_claim_id.is_empty():
			drop.be_attract_gold_magnet(target_pos)


## 从 [param phase] 的已保存余量生成钱堆；[param origin] 是清场或 Boss 死亡的世界坐标。
func spawn_first_clear_coins(phase: StagePhaseDefinition, origin: Vector2) -> void:
	var claim_id: String = AdventureRewardService.first_clear_claim_id(phase) # 每个阶段单独持久化。
	var counts: Dictionary = AdventureRewardService.pending_first_clear_coins(
		Global.global_game_state.adventure_state, claim_id) # 包括先前通关后未拾取的余量。
	if counts.is_empty():
		return
	var scenes: Dictionary[String, PackedScene] = {
		"diamond": SceneRegistry.COIN_DIAMOND,
		"gold": SceneRegistry.COIN_GOLD,
		"silver": SceneRegistry.COIN_SILVER,
	} # 复用原版钱币场景与待机动画。
	var denominations: Array[String] = [] # 一枚实体对应一个面额键。
	for denomination: String in scenes: # 只实例化三种已知钱币。
		for _copy: int in range(int(counts.get(denomination, 0))): # 展开此面额的剩余枚数。
			denominations.append(denomination)
	denominations.shuffle()

	var parent: Node2D = dim_coin.all_drop_coin_parent # 战场掉落画布随相机移动。
	var viewport: Rect2 = get_viewport().get_visible_rect() # 在可见范围内安排钱堆。
	var canvas_to_screen: Transform2D = parent.get_canvas_transform() # 世界坐标到屏幕坐标。
	var screen_to_local: Transform2D = parent.get_global_transform_with_canvas().affine_inverse() # 抛出需要父节点局部坐标。
	var screen_origin: Vector2 = (canvas_to_screen * origin).clamp(
		viewport.position + Vector2(50, 80), viewport.end - Vector2(50, 50)) # 避免屏外 Boss 生成看不到的抛洒。
	var center_x: float = 0.67 if phase.kind == StagePhaseDefinition.Kind.NIGHTMARE else 0.33 # 两阶段的钱堆并排。
	if AdventureSession.active_stage != null and not AdventureSession.active_stage.terminal_key_id.is_empty():
		# 有终末阶段时为三组首通钱堆留出位置，避免续战后叠在一起。
		match phase.kind:
			StagePhaseDefinition.Kind.NORMAL:
				center_x = 0.17
			StagePhaseDefinition.Kind.NIGHTMARE:
				center_x = 0.50
			StagePhaseDefinition.Kind.TERMINAL:
				center_x = 0.83
	var center: Vector2 = viewport.position + viewport.size * Vector2(center_x, 0.65) # 钱堆中心落在战场下半部。
	var spacing: Vector2 = viewport.size * Vector2(0.051, 0.072) # 相邻落点的屏幕间距。
	var row_count: int = ceili(float(denominations.size()) / FIRST_CLEAR_COLUMNS) # 末行可能未排满。
	var sounded: Array[String] = [] # 各面额只播一次抛出或落地音效。
	for index: int in range(denominations.size()): # 按打乱后的顺序在每个落点生成一枚。
		var denomination: String = denominations[index] # 当前实体的面额键。
		var coin: Coin = scenes[denomination].instantiate() as Coin # 每枚钱币独立拾取与入账。
		coin.first_clear_claim_id = claim_id
		coin.first_clear_denomination = denomination
		coin.coin_value = AdventureRewardService.FIRST_CLEAR_COIN_VALUES[denomination]
		coin.exist_time = 0.0
		coin.auto_collect_on_landing = false
		coin.duration = randf_range(0.42, 0.82)
		coin.peak_height = randf_range(75.0, 125.0)
		coin.scale = Vector2.ONE * 0.8
		if sounded.has(denomination):
			coin.launch_sound = &""
			coin.landing_sound = &""
		else:
			sounded.append(denomination)
		coin.setup(dim_coin.coin_bank_label.marker_2d_coin_target)
		parent.add_child(coin)
		coin.position = screen_to_local * screen_origin
		var row: int = floori(float(index) / FIRST_CLEAR_COLUMNS) # 从零开始的落点行号。
		var row_size: int = mini(FIRST_CLEAR_COLUMNS, denominations.size() - row * FIRST_CLEAR_COLUMNS) # 用实际列数居中。
		var offset: Vector2 = Vector2(index % FIRST_CLEAR_COLUMNS - (row_size - 1) * 0.5,
			row - (row_count - 1) * 0.5) * spacing # 相对钱堆中心的屏幕坐标。
		var landing: Vector2 = center + offset + Vector2(randf_range(-8, 8), randf_range(-6, 6)) # 打散规整的落点。
		coin.launch(screen_to_local * landing - coin.position)
		# 普通结算后的续战提示会暂停战斗，钱堆仍在提示框后落地。
		coin.tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)


## 普通掉落立即整批入账；首通钱币的飞行按 [param sequence] 的白屏时间轴启动。
func start_victory_collection(sequence: Tween) -> void:
	_collect_ordinary_drops()
	var delay := 0.18 # 普通掉落入账后，到首枚钱币飞出的间隔（秒）。
	var batch_size := 1 # 批大小从 1 递增到 4，再从 1 开始。
	var batch_remaining := batch_size # 当前批内尚未排入时间轴的枚数。
	for drop: Node in dim_coin.all_drop_coin_parent.get_children(): # 已手动拾取的钱币沿用现有飞行。
		if not drop is Coin or drop.first_clear_claim_id.is_empty() or drop.is_get:
			continue
		if drop.button != null:
			drop.button.disabled = true
		sequence.parallel().tween_callback(
			drop.collect.bind(FIRST_CLEAR_FLIGHT_SECONDS, batch_remaining == batch_size)).set_delay(delay)
		delay += FIRST_CLEAR_COIN_INTERVAL
		batch_remaining -= 1
		if batch_remaining == 0:
			delay += FIRST_CLEAR_BATCH_GAP
			batch_size = batch_size % 4 + 1
			batch_remaining = batch_size


## 离场前收取白屏期间迟到的掉落，也补收低帧率下尚未入账的钱币。
func finish_victory_collection() -> void:
	_collect_ordinary_drops()
	for drop: Node in dim_coin.all_drop_coin_parent.get_children(): # 此时普通掉落已整批收取。
		if drop is Coin and not drop.first_clear_claim_id.is_empty():
			drop.collect_now()


## 一次性收取在场的常规钱币、材料与花园礼盒，包含已在飞行中的钱币或材料。
func _collect_ordinary_drops() -> void:
	for drop: Node in dim_coin.all_drop_coin_parent.get_children(): # 两类战场掉落共用父节点。
		if drop is Coin and not drop.first_clear_claim_id.is_empty():
			continue
		if drop is BattlePickup:
			drop.collect_now()
	for drop: Node in dim_garden_plant.all_drop_garden_plant_parent.get_children(): # 花园礼盒使用独立父节点及入账逻辑。
		if drop is Present and not drop.is_queued_for_deletion():
			drop.collect()


