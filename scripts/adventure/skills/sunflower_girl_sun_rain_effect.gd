## 向日葵娘额外触发一轮生产，再向当前棋盘错峰投放十份标准阳光。
extends CharacterSkillEffect

## 每个分区落下一枚阳光，五列两行避免拾取点扎堆。
const RAIN_LAYOUT := Vector2i(5, 2)
## 额外天降阳光的单枚面值。
const SUN_VALUE: int = 25
## 第一枚在 Cut-in 开始退场附近从视口上方出现，单位为实际秒。
const RAIN_LEAD: float = 0.86

## [param context] 必须属于可施放的战斗，并且存在本关的阳光掉落层。
func can_execute(context: CharacterSkillContext) -> bool:
	return context != null and context.is_active() and is_instance_valid(context.game.suns) \
		and context.game.suns.is_inside_tree() and not context.game.suns.is_queued_for_deletion()

## [param context] 中的各株生产植物立即结算一次；有无产阳植物均会安排额外天降阳光。
func execute(context: CharacterSkillContext) -> bool:
	var source: RepeaterShotContext = context.state_source() # 延时掉落不能穿过续战阶段或轮次。
	if source == null:
		return false
	var cells: Array[PlantCell] = context.board.cells() # 同一份地块索引用于分布范围与即时生产。
	_queue_rain(source, cells)
	_trigger_production(source, cells)
	return true

## 为 [param source] 中 [param cells] 上存活的友方生产植株结算一次，合并本次产出的音效。
func _trigger_production(source: RepeaterShotContext, cells: Array[PlantCell]) -> void:
	var seen: Dictionary[int, bool] = {} # 实体跨格占用时只生产一次。
	var produced: bool = false # 一次施放最多播放一个生产声。
	for cell: PlantCell in cells: # 读取棋盘现有的植株层和伴生层。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion():
			continue
		for plant: Plant000Base in cell.living_plants(): # 生产事件可能同步改变棋盘，再次核对来源和目标。
			if not source.is_active():
				return
			if not is_instance_valid(plant) or plant.is_hypno:
				continue
			var id: int = plant.get_instance_id() # 每株实例保留自己的转职、幼体和成熟产值。
			if seen.has(id):
				continue
			seen[id] = true
			var producer := plant.get_node_or_null(^"CreateSunComponent") as CreateSunComponent # 按生产能力选株。
			if producer != null and producer.produce_for_skill():
				produced = true
	if produced:
		SoundManager.play_character_SFX(&"Throw1")

## 将 [param cells] 的可见部分分成十区，以 [param source] 所属战场的时间轴错峰落下。
func _queue_rain(source: RepeaterShotContext, cells: Array[PlantCell]) -> void:
	var game: MainGameManager = source.game # 由整场战斗持有时间轴，退出场景时自动释放。
	var screen: Rect2 = game.get_viewport().get_visible_rect() # 视口坐标使落点能避开卡栏及屏幕边缘。
	var safe_area := Rect2(screen.position + screen.size * Vector2(0.12, 0.25), screen.size * Vector2(0.78, 0.62)) # 小视口也保留拾取边距。
	var canvas: Transform2D = game.get_canvas_transform() # 将世界棋盘与实际可见区对齐。
	var area: Rect2 = safe_area.intersection(canvas * BoardQueries.bounds(cells)) # 优先覆盖可见的种植区。
	if area.size.x < safe_area.size.x * 0.60 or area.size.y < safe_area.size.y * 0.6:
		area = safe_area # 稀疏或移动棋盘也保持分散、可拾取。
	var to_world: Transform2D = canvas.affine_inverse() # 落点随此后的相机运动与战场保持一致。
	var pitch: Vector2 = area.size / Vector2(RAIN_LAYOUT) # 每枚独占一个分区，抖动小于分区边距。
	var random := RandomNumberGenerator.new() # 这里只为演出采样，独立于自然刷怪和掉落随机流。
	var count: int = RAIN_LAYOUT.x * RAIN_LAYOUT.y # 固定十份标准天降阳光。
	var offset: int = random.randi_range(0, count - 1) # 每次由不同方向开始，仍覆盖全部分区。
	var timeline: Tween = game.create_tween().set_ignore_time_scale(true) # 错峰跟随 Cut-in 的实际时间，暂停照常停止。
	timeline.tween_interval(RAIN_LEAD)
	for index: int in range(count): # 与十互质的步长跳过相邻列，并交错上下两层。
		var slot: int = (offset + index * 7) % count # 每个分区恰好访问一次。
		var column: int = slot % RAIN_LAYOUT.x # 分区横向索引。
		var row: int = 0 if slot % 2 == 0 else 1 # 同列两枚落在不同深度。
		var jitter := Vector2(random.randf_range(-0.22, 0.22), random.randf_range(-0.20, 0.20)) # 同时打破规则横线与纵线。
		var landing: Vector2 = area.position + pitch * (Vector2(column, row) + Vector2(0.5, 0.5) + jitter) # 本枚真实落点。
		var origin := Vector2(landing.x + pitch.x * random.randf_range(-0.40, 0.40), screen.position.y - screen.size.y * 0.10) # 从屏外略带侧滑入场。
		var seconds: float = 0.88 + (landing.y - origin.y) / screen.size.y * 0.65 + random.randf_range(-0.13, 0.13) # 深处多飞一会，入场先后与触地先后错开。
		timeline.tween_callback(_drop_sun.bind(source, to_world * origin, to_world * landing, seconds))
		if index < count - 1:
			timeline.tween_interval(random.randf_range(0.058, 0.113))

## [param source] 仍有效时，将一枚阳光从 [param origin] 落到 [param landing]，持续 [param seconds] 游戏秒。
func _drop_sun(source: RepeaterShotContext, origin: Vector2, landing: Vector2, seconds: float) -> void:
	if source.is_active():
		BattleSunDrop.spawn_falling(source.game, origin, landing, SUN_VALUE, seconds)
