## 共享 Alpha 剪影图集。脏格分批覆写，未到采样期的格继续供投影使用。
extends SubViewport

## 角色状态中保留精灵句柄和独占图集格。
const Caster = preload("res://scripts/battle/environment/battle_shadow_caster.gd")
## 动画帧的原纹理区域与当前部件变换。
const Part = preload("res://scripts/battle/environment/battle_silhouette_part.gd")
## 单格含透明外边的像素尺寸。
const TILE := Vector2i(48, 56)
## 图集格排列，一帧最多容纳 128 个角色。
const GRID := Vector2i(16, 8)
## 图集容量。
const CAPACITY := GRID.x * GRID.y
## 图集中为线性过滤预留的透明像素。
const GUTTER := 2.0
## 稀疏和密集场景的姿态采样间隔，单位秒。
const POSE_INTERVAL := 1.0 / 24.0
## 密集场景的姿态采样间隔，单位秒。
const CROWDED_INTERVAL := 1.0 / 18.0
## 每帧姿态准备上限，避免密集场景同时重算整张图集。
const UPDATE_BUDGET := 38

## 已提交的姿态批次数。
var generation: int
## 每个图集格的现任实体。空格由新进入灯区的实体使用。
var _slots: Array[Caster] = []
## 本帧需要覆盖透明底的格列表。
var _repaint: Array[Vector2i] = []
## 更新格的精灵批次，按纹理分组。
var _draws: Dictionary[RID, Array] = {}
## 当前为哪个活动帧对占用格做标记。
var _use_frame: int
## 本轮循环采样从哪个格继续。
var _next_slot: int
## 用透明色覆盖脏格的画布。
var _clear: Node2D
## 在透明格上画出当前姿态的画布。
var _canvas: Node2D

## 创建图集两层共用画布。
func _ready() -> void:
	size = TILE * GRID
	_slots.resize(CAPACITY)
	_clear = Node2D.new()
	_clear.z_index = -1
	var material := ShaderMaterial.new() # 所有脏格共用透明覆写材质。
	material.shader = preload("res://shaders/environment/battle_shadow_clear_tile.gdshader")
	_clear.material = material
	_clear.draw.connect(_clear_tiles)
	add_child(_clear)
	_canvas = Node2D.new()
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_canvas.draw.connect(_draw_tiles)
	add_child(_canvas)

## 根据 [param active] 更新图集占用，用战斗秒数 [param now] 限制采样频率。
func prepare(active: Array[Caster], now: float) -> void:
	_use_frame += 1
	for caster: Caster in active: # 标记仍可见的既有格。
		caster.atlas_use = _use_frame
	for index: int in range(CAPACITY): # 回收离开灯区的格，未刷新的新占用者不会使用它。
		var caster: Caster = _slots[index] # 保留灯区内其他角色的图集地址。
		if caster != null and caster.atlas_use != _use_frame:
			caster.tile = -1
			caster.generation = -1
			_slots[index] = null
	for caster: Caster in active: # 活跃列表已由投影器裁剪到容量。
		if caster.tile >= 0:
			continue
		caster.tile = _slots.find(null)
		caster.pose_due = now
		_slots[caster.tile] = caster
	_repaint.clear()
	_draws.clear()
	var interval: float = POSE_INTERVAL if active.size() < 36 else CROWDED_INTERVAL # 密集时约 18 Hz。
	for ignored: int in range(CAPACITY): # 循环、公平地刷新到期格。
		var caster: Caster = _slots[_next_slot] # 下一次从未消费的格继续。
		_next_slot = (_next_slot + 1) % CAPACITY
		if caster == null or now < caster.pose_due:
			continue
		_capture(caster)
		caster.pose_due = now + interval
		if _repaint.size() >= UPDATE_BUDGET:
			break
	if not _repaint.is_empty():
		generation += 1
		_clear.queue_redraw()
		_canvas.queue_redraw()
		render_target_update_mode = SubViewport.UPDATE_ONCE

## 刷新 [param caster] 的当前 Alpha 和姿态范围。
func _capture(caster: Caster) -> void:
	if caster.dirty:
		caster.parts.clear()
		if caster.body is Sprite2D or caster.body is AnimatedSprite2D:
			caster.parts.append(Part.new(caster.body))
		for kind: String in ["Sprite2D", "AnimatedSprite2D"]: # 拓扑事件才重新查找子精灵。
			for sprite: Node2D in caster.body.find_children("*", kind, true, false): # 包括附加的护甲部件。
				caster.parts.append(Part.new(sprite))
		caster.dirty = false
	var foot: Vector2 = caster.foot.global_position # 将角色移动从姿态采样中剥离。
	var bounds := Rect2() # 动态范围只用于取纹理，不作为身体高度标定。
	var owner_alpha: float = caster.owner.modulate.a if caster.owner != caster.body else 1.0 # 跟随角色整体死亡淡出。
	var body_alpha: float = caster.body.modulate.a # 身体级透明度对下层所有部件生效。
	for part: Part in caster.parts: # 使用角色现有精灵、帧号和纹理。
		var sprite: Node2D = part.sprite # 变换后的外观是原 Alpha 的来源。
		part.texture = null
		if not is_instance_valid(sprite) or not sprite.is_visible_in_tree():
			continue
		if sprite != caster.body and not caster.body.is_ancestor_of(sprite):
			continue
		part.opacity = owner_alpha * sprite.self_modulate.a * sprite.modulate.a
		if sprite != caster.body:
			part.opacity *= body_alpha
		if part.opacity < 0.025 or not part.read_frame():
			continue
		part.pose = sprite.global_transform
		part.pose.origin -= foot
		var region: Rect2 = part.pose * Rect2(part.rect.position, part.rect.size.abs()) # 含精灵旋转和缩放。
		bounds = region if not bounds.has_area() else bounds.merge(region)
	var cell: Vector2i = tile_coords(caster.tile) # 独占格的左上地址。
	_repaint.append(cell)
	var padding: Vector2 = bounds.size * GUTTER / (Vector2(TILE) - Vector2.ONE * GUTTER * 2.0) # 留出不会串样的透明边。
	caster.pose_bounds = Rect2(bounds.position - padding, bounds.size + padding * 2.0)
	caster.generation = generation + 1
	if bounds.has_area():
		var scale_to_tile: Vector2 = Vector2(TILE) / caster.pose_bounds.size # 原位姿态只在图集打包时缩放。
		var layout := Transform2D(0.0, scale_to_tile, 0.0, Vector2(cell * TILE) - caster.pose_bounds.position * scale_to_tile) # 映射到图集像素。
		for part: Part in caster.parts: # 分组后可复用原动画纹理的提交批次。
			if part.texture != null:
				part.atlas_pose = layout * part.pose
				_draws.get_or_add(part.texture.get_rid(), []).append(part)

## 将线性格 [param index] 转为图集行列。
static func tile_coords(index: int) -> Vector2i:
	return Vector2i(index % GRID.x, floori(float(index) / GRID.x))

## 只清空本次更新格，其他格保留最近一次姿态。
func _clear_tiles() -> void:
	for cell: Vector2i in _repaint: # 含透明隔离区的整格。
		_clear.draw_rect(Rect2(Vector2(cell * TILE), Vector2(TILE)), Color.WHITE)

## 对刷新格提交原始动画的 Alpha。
func _draw_tiles() -> void:
	for batch: Array in _draws.values(): # 同纹理精灵可以合批。
		for part: Part in batch: # Alpha 并集对组内顺序不敏感。
			_canvas.draw_set_transform_matrix(part.atlas_pose)
			_canvas.draw_texture_rect_region(part.texture, part.rect, part.source, Color(1.0, 1.0, 1.0, part.opacity))
