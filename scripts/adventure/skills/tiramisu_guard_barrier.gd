## 花冠守护的共享屏障。立盾立即生效，退场画面可在战斗效果结束后播放完毕。
extends FriendlyBattleBarrier
class_name TiramisuGuardBarrier

## 屏障在未破裂时持续的游戏秒数。
const DURATION: float = 20.0
## 植物生命组件的独立百分比减伤来源。
const PLANT_REDUCTION: float = 0.70
## 实际屏障横截面宽度，单位为世界像素。
const WALL_WIDTH: float = 84.0
## 命中音最短间隔，杂兵在多行同时啃咬时只发出一声清晰撞击。
const IMPACT_INTERVAL: float = 0.51
## 位置和当前视效由同一个战斗宿主持有。
const Visual = preload("res://scripts/adventure/skills/tiramisu_guard_visual.gd")
## 立盾底击、分层钟音和晶片升起声音。
const RAISE: AudioStream = preload("res://assets/adventure/audio/skills/tiramisu_guard_raise.ogg")
## 克制的近场晶体撞击音。
const IMPACT: AudioStream = preload("res://assets/adventure/audio/skills/tiramisu_guard_impact.ogg")
## 退场时的柔和尾铃，击碎时使用较快音高与碎音叠加。
const RELEASE: AudioStream = preload("res://assets/adventure/audio/skills/tiramisu_guard_release.ogg")

## 施放时冻结的战场、轮次和阶段。
var _battle: RepeaterShotContext
## 屏障世界包围盒，竖向覆盖全部行的攻击高度。
var _wall: Rect2
## 当前保护过的植物，用实例身份去重，结束时只撤销本次施放的来源。
var _plants: Dictionary[int, Plant000Base] = {}
## 仍在订阅种植事件的棋盘格。
var _cells: Array[PlantCell] = []
## 剩余保护时间，单位为游戏秒。
var _remaining: float = DURATION
## 下一个撞击音可以播放前的游戏秒数。
var _impact_wait: float = 0.0
## 待消费的命中纵坐标；未知时使用屏障中央。
var _contact_y: float = INF
## 实际扣血与视觉演出的单向边界。
var _visual: Visual

## 入树前绑定 [param battle]，在 [param world_x] 立盾并依据 [param bounds] 覆盖全部行。
func prepare(battle: RepeaterShotContext, world_x: float, bounds: Rect2) -> void:
	_battle = battle
	_wall = Rect2(world_x - WALL_WIDTH * 0.5, bounds.position.y - 45.0, WALL_WIDTH, bounds.size.y + 57.0)
	process_mode = Node.PROCESS_MODE_ALWAYS # 暂停仍可释放已结算战斗，时钟在暂停期间冻结。

## 完成原生角色初始化，同步装入碰撞与减伤来源。
func _ready() -> void:
	super()
	global_position = Vector2(_wall.get_center().x, _wall.position.y)
	var plane := RectangleShape2D.new() # 两个通道共享本次施放的尺寸，不污染模板或其他施放。
	plane.size = _wall.size
	hurt_box_component.position.y = _wall.size.y * 0.5 # 投射物瞄向可受击平面的中央。
	for path: NodePath in [^"HurtBoxComponent/HurtBoxDetection/CollisionShape2D",
			^"HurtBoxComponent/HurtBoxReal/CollisionShape2D"]: # 啃食检测与弹体命中使用相同范围。
		var shape: CollisionShape2D = get_node(path) # 形状锚点在屏障几何中央。
		shape.position = Vector2.ZERO
		shape.shape = plane
	add_to_group(GROUP)
	_cells = _battle.board.cells()
	for cell: PlantCell in _cells: # 每格已有植物和后续新种植共享同一来源。
		cell.signal_plant_create.connect(_on_plant_created)
		_protect_cell(cell)
	_visual = Visual.new(_wall.size, _cells)
	add_child(_visual)
	hp_component.combat_health_lost.connect(_on_health_lost)
	SoundManager.play_world_sfx(RAISE, self, _wall.get_center(), -1.0, 1.0, &"guard_raise", true, 1)

## [param delta] 是本物理步的游戏秒数；暂停时只检查原战斗是否仍有效。
func _physics_process(delta: float) -> void:
	if not _battle.is_active():
		_finish(false, false)
		queue_free()
		return
	if get_tree().paused or is_death:
		return
	_remaining = maxf(0.0, _remaining - delta)
	_impact_wait = maxf(0.0, _impact_wait - delta)
	if _remaining <= 0.00001:
		_finish(false, true)

## 保存 [param world_y]，让紧接着确认的生命损失在真实接触位置产生涟漪。
func note_contact(world_y: float) -> void:
	_contact_y = world_y - global_position.y

## 血量归零，立即解除拦截与全场减伤，并播放击碎演出。
func character_death():
	_finish(true, true)

## [param broken] 区分击碎和到时消散。[param animated] 在原战斗仍有效时保留尾动画。
func _finish(broken: bool, animated: bool) -> void:
	if is_death:
		return
	remove_from_group(GROUP)
	hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	_release_protection()
	super.character_death()
	if animated:
		_visual.dismiss(broken)
		SoundManager.play_world_sfx(RELEASE, self, _wall.get_center(), -2.0 if broken else 0.0,
			1.18 if broken else 1.0, &"guard_release", true, 1)
		_visual.dismissed.connect(queue_free, CONNECT_ONE_SHOT)

## [param cell] 已提交 [param _type] 的种植，既适用于普通种植，也适用于复生和伴生。
func _on_plant_created(cell: PlantCell, _type: CharacterRegistry.PlantType) -> void:
	if is_intercepting() and _battle.is_active():
		_protect_cell(cell)

## [param cell] 上所有活株受益，包括承托层、外壳和不占格的伴生。
func _protect_cell(cell: PlantCell) -> void:
	for plant: Plant000Base in cell.living_plants(): # 同一植物重复通知时不再写生命组件。
		var id: int = plant.get_instance_id() # 使用实例 ID 区分同格新旧植物。
		if not _plants.has(id):
			_plants[id] = plant
			plant.hp_component.damage_reduction.set_source(get_instance_id(), PLANT_REDUCTION)

## 停止监听新植物，撤销本次施放留在生命组件上的减伤。
func _release_protection() -> void:
	for cell: PlantCell in _cells: # 棋盘可能正在释放，失效地块无需断开。
		if is_instance_valid(cell):
			cell.signal_plant_create.disconnect(_on_plant_created)
	_cells.clear()
	for plant: Plant000Base in _plants.values(): # 已经释放的植物没有需要撤销的组件。
		if is_instance_valid(plant) and is_instance_valid(plant.hp_component):
			plant.hp_component.damage_reduction.set_source(get_instance_id(), 0.0)
	_plants.clear()

## [param amount] 是实际生命损失。受击音受总频率限制，涟漪保留每行碰撞信息。
func _on_health_lost(amount: int) -> void:
	var contact_y := _contact_y if is_finite(_contact_y) else _wall.size.y * 0.5 # 音效与涟漪共用实际命中高度。
	_visual.impact(contact_y, amount)
	_contact_y = INF
	if _impact_wait <= 0.0:
		_impact_wait = IMPACT_INTERVAL
		SoundManager.play_world_sfx(IMPACT, self, Vector2(global_position.x, global_position.y + contact_y),
			-7.0 if amount < 350 else -1.5, randf_range(0.94, 1.06), &"guard_impact")

## 退出或重开时，即使还没有走到超时也撤销减伤。
func _exit_tree() -> void:
	_release_protection()
