extends MainGameSubManager
class_name DropItemManager
## 掉落道具管理器, 管理掉落金币、花盆
## 主游戏场景和花园场景使用

## 每枚首通钱币最多采样的落点数；钱堆较密时从候选中挑出最宽松的落点。
const FIRST_CLEAR_LANDING_ATTEMPTS := 20
## 首通钱币优先保留的中心间距，占视口短边的比例。
const FIRST_CLEAR_COIN_GAP_RATIO := 0.065
## 首通钱币逐枚入场的间隔（真实秒）。
const FIRST_CLEAR_DROP_INTERVAL := 0.075
## 胜利保底和首通钱币在奖杯收取时的飞行时间（秒）。
const VICTORY_FLIGHT_SECONDS := 0.26
## 首通同批两枚之间的启动间隔（秒）。
const FIRST_CLEAR_COIN_INTERVAL := 0.035
## 每批结束后额外留出的间隔（秒），使 1、2、3、4 枚的节奏可辨。
const FIRST_CLEAR_BATCH_GAP := 0.065
## 胜利保底每行最多七堆，落点间距留出各物品的点击范围（屏幕像素）。
const VICTORY_ITEM_COLUMNS := 7
## 胜利保底的列距和行距（屏幕像素）。
const VICTORY_ITEM_SPACING := Vector2(76.0, 76.0)

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


## 从登记 Boss 的死亡坐标 [param origin] 抛出一颗钻石，留在场上供手动或奖杯收取。
## 起点和落点都夹在可见区域内，靠屏幕边缘死亡也能拾取。
func spawn_boss_diamond(origin: Vector2) -> void:
	if not is_instance_valid(dim_coin) or not is_instance_valid(dim_coin.all_drop_coin_parent):
		return
	var parent: Node2D = dim_coin.all_drop_coin_parent # 使用本关的掉落层与金币目标，不广播到其他场景。
	var viewport: Rect2 = get_viewport().get_visible_rect() # 保留钻石整张点击区域的屏幕边距。
	var margin: float = minf(48.0, minf(viewport.size.x, viewport.size.y) * 0.5) # 极小视口也不反转夹取范围。
	var bounds: Rect2 = viewport.grow(-margin) # 保底钻石的起落点范围。
	var canvas: Transform2D = parent.get_canvas_transform() # 将死亡坐标转换到视口空间再限制位置。
	var start: Vector2 = (canvas * origin).clamp(bounds.position, bounds.end) # 从最靠近死亡点的可见位置出现。
	var landing: Vector2 = (start + Vector2(randf_range(-36.0, 36.0), 56.0)).clamp(bounds.position, bounds.end) # 向前抛落。
	var to_local: Transform2D = parent.get_global_transform_with_canvas().affine_inverse() # 抛掷偏移采用掉落层局部坐标。
	dim_coin.spawn_coin(SceneRegistry.COIN_DIAMOND, canvas.affine_inverse() * start,
		to_local.basis_xform(landing - start), true)


## 在 [param origin] 掷出一份旗帜波配方 [param recipe_id]；拾取时入账，未拾取则留给奖杯收取。
func spawn_flag_recipe(recipe_id: StringName, origin: Vector2) -> void:
	var pickup: MaterialPickup = BattleDropService.spawn(BattleDropService.MaterialPickupScene,
		dim_coin.all_drop_coin_parent, dim_coin.coin_bank_label.marker_2d_coin_target, origin, true) as MaterialPickup # 配方不随时间消失。
	if pickup != null:
		pickup.setup_item(recipe_id)
		BattleDropService.throw_pickup(pickup)


## 从奖杯的世界坐标 [param origin] 抛出已入账的 [param items]，相同物品合为一堆。
## 实体留在场上供手动收取，也可随奖杯批量收取。
func spawn_victory_floor_items(items: Dictionary, origin: Vector2) -> void:
	if items.is_empty():
		return
	var parent: Node2D = dim_coin.all_drop_coin_parent # 与钱币共用相机跟随的掉落层。
	var viewport: Rect2 = get_viewport().get_visible_rect() # 落点在可见战场内计算。
	var canvas: Transform2D = parent.get_canvas_transform() # 世界坐标转换到屏幕坐标。
	var screen_to_local: Transform2D = parent.get_global_transform_with_canvas().affine_inverse() # 抛物线在父节点局部坐标中执行。
	var screen_origin: Vector2 = (canvas * origin).clamp(
		viewport.position + Vector2(42.0, 100.0), viewport.end - Vector2(42.0, 50.0)) # 屏外清场时从屏幕可见边缘抛出。
	var world_origin: Vector2 = canvas.affine_inverse() * screen_origin # 掉落服务接收的世界坐标。
	var columns: int = mini(VICTORY_ITEM_COLUMNS, items.size()) # 一行的最大物品数。
	var rows: int = ceili(float(items.size()) / columns) # 末行可能未填满。
	var extent: Vector2 = Vector2(columns - 1, rows - 1) * VICTORY_ITEM_SPACING * 0.5 # 网格最外侧落点到中心的距离。
	var direction: float = -1.0 if screen_origin.y > viewport.get_center().y else 1.0 # 朝可用空间更大的一侧落地。
	var center: Vector2 = (screen_origin + Vector2(0.0, direction * (86.0 + extent.y))).clamp(
		viewport.position + Vector2(42.0, 100.0) + extent,
		viewport.end - Vector2(42.0, 42.0) - extent) # 给奖杯与物品的点击区域留出间隔。
	var target: Node2D = dim_coin.coin_bank_label.marker_2d_coin_target # 复用战场物品的收取飞行锚点。
	var ids: Array = items.keys() # 保底记录使用结算时的物品顺序。
	for index: int in range(ids.size()): # 每种物品仅生成一个掉落堆。
		var id: String = ids[index] # 当前物品的静态 ID。
		var pickup: MaterialPickup = BattleDropService.spawn_settled_item(parent, target, world_origin,
			StringName(id), int(items[id])) # 直接使用已结算的物品和份数。
		if pickup == null:
			continue
		var row: int = floori(float(index) / columns) # 当前落点所在的零基行号。
		var row_size: int = mini(columns, ids.size() - row * columns) # 按实际列数居中末行。
		var offset: Vector2 = Vector2(index % columns - (row_size - 1) * 0.5,
			row - (rows - 1) * 0.5) * VICTORY_ITEM_SPACING # 网格内相对中心的偏移。
		BattleDropService.throw_pickup(pickup, screen_to_local * (center + offset) - pickup.position)


## 从 [param phase] 的已保存余量生成钱币，在视口中央播放下落与回弹。
## 返回演出时间轴供结算界面等待；没有余量时返回 null。
func spawn_first_clear_coins(phase: StagePhaseDefinition) -> Tween:
	var claim_id: String = AdventureRewardService.first_clear_claim_id(phase) # 每个阶段单独持久化。
	var counts: Dictionary = AdventureRewardService.pending_first_clear_coins(
		Global.global_game_state.adventure_state, claim_id) # 包括先前通关后未拾取的余量。
	if counts.is_empty():
		return null
	var scenes: Dictionary[String, PackedScene] = {
		"diamond": SceneRegistry.COIN_DIAMOND,
		"gold": SceneRegistry.COIN_GOLD,
		"silver": SceneRegistry.COIN_SILVER,
	} # 复用原版钱币场景与待机动画。
	var denominations: Array[String] = [] # 一枚实体对应一个面额键。
	for denomination: String in scenes: # 只实例化三种已知钱币。
		for _copy: int in range(int(counts.get(denomination, 0))): # 展开此面额的剩余枚数。
			denominations.append(denomination)
	if denominations.is_empty():
		return null
	denominations.shuffle()

	var parent: Node2D = dim_coin.all_drop_coin_parent # 战场掉落画布随相机移动。
	var viewport: Rect2 = get_viewport().get_visible_rect() # 在可见范围内安排钱堆。
	var local_to_screen: Transform2D = parent.get_global_transform_with_canvas() # 掉落层的局部坐标转为视口坐标。
	var screen_to_local: Transform2D = local_to_screen.affine_inverse() # 将演出位置转换回钱币的父节点坐标。
	var landings: Array[Vector2] = [] # 记录续战留在场上的钱币及本次选中的落点。
	for drop: Node in parent.get_children(): # 给先前阶段仍可拾取的钱币留出间距。
		if drop is Coin and not drop.is_get and not drop.is_queued_for_deletion() \
				and not drop.first_clear_claim_id.is_empty():
			landings.append(local_to_screen * drop.position)
	var center: Vector2 = viewport.get_center() # 各阶段统一以可见屏幕的中心为堆心。
	var pile_scale: float = clampf(sqrt(float(denominations.size() + landings.size()) / 30.0), 0.35, 1.45) # 随场上总枚数扩大钱堆，保留屏幕边缘的空隙。
	var radii: Vector2 = viewport.size * Vector2(0.215, 0.225) * pile_scale # 中央落点区域的横纵半径。
	var gap: float = minf(viewport.size.x, viewport.size.y) * FIRST_CLEAR_COIN_GAP_RATIO # 屏幕坐标中的优先间距。
	var spawn_y: float = viewport.position.y - maxf(80.0, viewport.size.y * 0.11) # 从屏幕上沿外完整入场。
	var drift: float = viewport.size.x * 0.04 # 单枚钱币进场的最大横向偏移。
	var rebound: Vector2 = Vector2(0.0, -viewport.size.y * 0.017) # 落地后向屏幕上方轻弹的位移。
	var sounded: Array[String] = [] # 各面额只播一次进场或落地音效。
	var rain_seconds: float = 0.0 # 用最后一枚钱币的回弹结束时间控制后续界面。
	for index: int in range(denominations.size()): # 按打乱后的顺序错开入场，让三种钱币混在一起。
		var denomination: String = denominations[index] # 本枚钱币的面额键。
		var landing: Vector2 = _pick_first_clear_landing(center, radii, landings, gap * gap) # 本枚钱币的屏幕落点。
		landings.append(landing)
		var coin: Coin = scenes[denomination].instantiate() as Coin # 每枚钱币独立拾取与入账。
		coin.first_clear_claim_id = claim_id
		coin.first_clear_denomination = denomination
		coin.coin_value = AdventureRewardService.FIRST_CLEAR_COIN_VALUES[denomination]
		coin.exist_time = 0.0
		coin.scale = Vector2.ONE * 0.8
		if sounded.has(denomination):
			coin.launch_sound = &""
			coin.landing_sound = &""
		else:
			sounded.append(denomination)
		coin.setup(dim_coin.coin_bank_label.marker_2d_coin_target)
		coin.position = screen_to_local * Vector2(landing.x + randf_range(-drift, drift), spawn_y)
		parent.add_child(coin)
		rain_seconds = coin.fall_from_sky(screen_to_local * landing,
			screen_to_local * (landing + rebound), index * FIRST_CLEAR_DROP_INTERVAL)

	# 随战斗节点释放的独立时间轴，玩家提前拾取钱币时仍能推进结算界面。
	var presentation: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	presentation.tween_interval(rain_seconds)
	return presentation


## 在以 [param center] 为中心、[param radii] 为横纵半径的椭圆内挑选屏幕落点。
## 优先返回到所有 [param landings] 的距离平方均达到 [param gap_squared] 的候选。
## 尝试次数用完时，返回离最近一枚钱币最远的候选。
func _pick_first_clear_landing(center: Vector2, radii: Vector2,
		landings: Array[Vector2], gap_squared: float) -> Vector2:
	if landings.is_empty():
		return center
	var best: Vector2 = center # 未达到优先间距时采用的候选落点。
	var best_clearance: float = -1.0 # 最佳候选到最近落点的距离平方，负值表示尚未找到候选。
	for _attempt: int in range(FIRST_CLEAR_LANDING_ATTEMPTS): # 限制密集钱堆的采样开销。
		var candidate: Vector2 = center + Vector2.from_angle(randf() * TAU) * sqrt(randf()) * radii # 在椭圆内均匀采样面积。
		var clearance: float = INF # 候选到最近落点的距离平方；尚无落点时直接采用候选。
		for landing: Vector2 in landings: # 每个已选落点都可能挡住本枚钱币。
			clearance = minf(clearance, candidate.distance_squared_to(landing))
		if clearance >= gap_squared:
			return candidate
		if clearance > best_clearance:
			best = candidate
			best_clearance = clearance
	return best


## 普通掉落立即整批入账；保底和首通钱币的飞行按 [param sequence] 的白屏时间轴启动。
func start_victory_collection(sequence: Tween) -> void:
	_collect_ordinary_drops()
	var delay := 0.18 # 普通掉落入账后，到首枚钱币飞出的间隔（秒）。
	var batch_size := 1 # 批大小从 1 递增到 4，再从 1 开始。
	var batch_remaining := batch_size # 当前批内尚未排入时间轴的枚数。
	for drop: Node in dim_coin.all_drop_coin_parent.get_children(): # 已手动拾取的奖励沿用现有飞行。
		var pickup: BattlePickup = drop as BattlePickup # 掉落层也可能包含短暂的粒子节点。
		if pickup == null or not _is_victory_pickup(pickup) or pickup.is_get:
			continue
		if pickup.button != null:
			pickup.button.disabled = true
		if pickup is MaterialPickup:
			sequence.parallel().tween_callback(
				pickup.collect.bind(VICTORY_FLIGHT_SECONDS, false)).set_delay(pickup.duration)
			continue
		sequence.parallel().tween_callback(
			pickup.collect.bind(VICTORY_FLIGHT_SECONDS, batch_remaining == batch_size)).set_delay(delay)
		delay += FIRST_CLEAR_COIN_INTERVAL
		batch_remaining -= 1
		if batch_remaining == 0:
			delay += FIRST_CLEAR_BATCH_GAP
			batch_size = batch_size % 4 + 1
			batch_remaining = batch_size


## 离场前补收白屏期间迟到或仍在飞行的掉落。
func finish_victory_collection() -> void:
	_collect_ordinary_drops()
	for drop: Node in dim_coin.all_drop_coin_parent.get_children(): # 普通掉落入账后再补收胜利奖励。
		if drop is BattlePickup and _is_victory_pickup(drop):
			drop.collect_now()


## 判断 [param drop] 是否随胜利生成，并使用奖杯的收取时间轴。
func _is_victory_pickup(drop: Node) -> bool:
	return (drop is Coin and not drop.first_clear_claim_id.is_empty()) \
		or (drop is MaterialPickup and drop.settled_reward)


## 一次性收取常规钱币、材料与花园礼盒，包含已在飞行中的钱币或材料。
func _collect_ordinary_drops() -> void:
	for drop: Node in dim_coin.all_drop_coin_parent.get_children(): # 两类战场掉落共用父节点。
		if drop is BattlePickup and not _is_victory_pickup(drop):
			drop.collect_now()
	for drop: Node in dim_garden_plant.all_drop_garden_plant_parent.get_children(): # 花园礼盒使用独立父节点及入账逻辑。
		if drop is Present and not drop.is_queued_for_deletion():
			drop.collect()


