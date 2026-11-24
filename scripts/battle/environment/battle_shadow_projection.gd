## 组织角色剪影、地面投影和原位身体遮罩。光场只读取对应灯格。
extends Node

## 共享低分辨率姿态图集。
const Atlas = preload("res://scripts/battle/environment/battle_shadow_atlas.gd")
## GPU 地面投影的实例数据和细分网格。
const Ground = preload("res://scripts/battle/environment/battle_shadow_ground.gd")
## 单个角色的接地标定和主灯滞回。
const Caster = preload("res://scripts/battle/environment/battle_shadow_caster.gd")
## 灯的世界状态与覆盖函数。
const LightSource = preload("res://scripts/battle/environment/battle_light_source.gd")

## 在光场中画回原位身体剪影的批次。
@export var body_clear: MultiMeshInstance2D
## 暖光经过实心遮挡时的最大扣光比例。
@export_range(0.0, 1.0) var shadow_opacity := 0.87
## 普通轮廓横向投射到虚拟地面时的固定斜轴。不会跟着灯和脚点夹角旋转。
@export var horizontal_ground_axis := Vector2(1.0, 0.22)
## 以世界像素定义长影预算。仅参与安全高度上界和屏外筛选。
@export_range(40.0, 1200.0) var max_shadow_world_extent := 420.0
## 调整有限灯源的半影，仍限制在约一片图集纹素内。
@export_range(0.0, 2.0) var penumbra_scale := 0.76
## 候选灯至少比主灯亮多少，达到后才开始计时。
@export_range(0.0, 1.0) var light_hysteresis_ratio := 0.25
## 候选灯保持领先的战斗秒数。
@export_range(0.01, 1.0) var hysteresis_duration := 0.14
## 已确认切换时，各一段淡出和淡入时间。
@export_range(0.01, 0.3) var handoff_fade := 0.07

## 按角色实例号索引的稳定接地状态。
var _casters: Dictionary[int, Caster] = {}
## 活体部件新增时只标记对应表现根。
var _bodies: Dictionary[int, Caster] = {}
## 本帧通过几何和灯区筛选且能够提交的角色。
var _active: Array[Caster] = []
## 本帧已经获得遮挡格的投影灯。
var _emitters: Array[LightSource] = []
## 共享地面批次的参数表。
var _ground := Ground.new()

## 局部阴影格共用的视口。
@onready var _mask: SubViewport = $ShadowMaskAtlas
## 实际提交地面图元的批次。
@onready var casts: MultiMeshInstance2D = $ShadowMaskAtlas/Casts
## 保留源精灵 Alpha 的共享图集。
@onready var _atlas: Atlas = $ShadowMaskAtlas/SilhouetteAtlas

## 连接同一张剪影图集与两个批次，设定固定网格。
func _ready() -> void:
	_mask.size = Ground.LIGHT_GRID * Ground.LIGHT_TILE
	_ground.configure(casts, Atlas.CAPACITY, horizontal_ground_axis)
	var cast_material := casts.material as ShaderMaterial # 半影参数整个场景共享。
	cast_material.set_shader_parameter(&"penumbra_scale", penumbra_scale)
	body_clear.multimesh.instance_count = Atlas.CAPACITY
	body_clear.multimesh.visible_instance_count = 0
	for shader_material: ShaderMaterial in [cast_material, body_clear.material]: # 原位与地面共用 Alpha。
		shader_material.set_shader_parameter(&"silhouette_atlas", _atlas.get_texture())
		shader_material.set_shader_parameter(&"grid", Vector2(Atlas.GRID))
	# 表现根没有统一的嵌套变更信号，仅在新精灵入树时查找归属。
	get_tree().node_added.connect(_on_part_added)

## 遮挡视口纹理。调用者通过每灯格索引读取其中一个局部区域。
func mask_texture() -> Texture2D:
	return _mask.get_texture()

## 为 [param owner] 的 [param body] 建立投影。[param foot] 跟随实体脚点。
## [param reference_height] 与 [param body_height] 为固定原画、虚拟高度，单位均为世界像素。
func register_caster(body: Node2D, foot: Node2D, owner: Node2D, reference_height: float, body_height: float) -> void:
	var id: int = owner.get_instance_id() # 材质变化或换格不会改变实体身份。
	if body == null or foot == null or _casters.has(id):
		return
	var caster := Caster.new() # 姿态第一次进入灯区时才采样。
	caster.owner = owner
	caster.body = body
	caster.foot = foot
	caster.reference_height = maxf(1.0, reference_height)
	caster.body_height = maxf(0.0, body_height)
	_casters[id] = caster
	_bodies[body.get_instance_id()] = caster
	owner.tree_exited.connect(_check_departure.bind(id, body.get_instance_id()), CONNECT_DEFERRED)

## 处理退出的 [param id] 和注册时的 [param body_id]，移位同帧重新入树的角色继续沿用姿态。
func _check_departure(id: int, body_id: int) -> void:
	var caster: Caster = _casters.get(id) # 战场关闭时登记表可能已经释放。
	if caster != null and (not is_instance_valid(caster.owner) or not caster.owner.is_inside_tree()):
		_casters.erase(id)
		_bodies.erase(body_id)

## 将属于已登记角色的 [param node] 标为一次拓扑变更。
func _on_part_added(node: Node) -> void:
	if _bodies.is_empty() or not (node is Sprite2D or node is AnimatedSprite2D):
		return
	var part_parent: Node = node.get_parent() # 每新增一个精灵按祖先查找，不逐帧扫描。
	while part_parent != null:
		var caster: Caster = _bodies.get(part_parent.get_instance_id()) # 检查是否进入已登记的表现根。
		if caster != null:
			caster.dirty = true
			caster.pose_due = 0.0
			return
		part_parent = part_parent.get_parent()

## 按 [param projection] 和 [param bounds] 筛选可能进入可见遮罩的角色。
## [param lights] 是本帧灯光，[param now] 是战斗秒数。返回是否提交了局部遮挡图集。
func render_shadows(projection: Transform2D, bounds: Rect2, lights: Array[LightSource], now: float) -> bool:
	_emitters.clear()
	_reserve_slots(lights, true)
	_reserve_slots(lights, false)
	_active.clear()
	if not _emitters.is_empty():
		var world_area: Rect2 = (projection.affine_inverse() * bounds).grow(max_shadow_world_extent) # 屏外角色仍可能把影子投进来。
		for caster: Caster in _casters.values(): # 剪影尚在播放死亡动作时仍按现有姿态投射。
			if is_instance_valid(caster.owner) and not caster.owner.is_queued_for_deletion() \
					and is_instance_valid(caster.foot) and is_instance_valid(caster.body) and caster.body.is_visible_in_tree():
				var foot: Vector2 = caster.foot.global_position # 使用实体原先的地面标记。
				if world_area.has_point(foot) and caster.update_light(_emitters, foot, now,
						light_hysteresis_ratio, hysteresis_duration, handoff_fade):
					_active.append(caster)
	if _active.size() > Atlas.CAPACITY:
		_active.sort_custom(func(a: Caster, b: Caster) -> bool: return a.light_power > b.light_power)
		_active.resize(Atlas.CAPACITY)
	_atlas.prepare(_active, now)
	return _submit(projection, bounds)

## 为 [param lights] 中 [param priority] 相符的投影灯分配共享图集格。
## 分配只改遮挡地址，灯片的合成顺序仍由光场维护。
func _reserve_slots(lights: Array[LightSource], priority: bool) -> void:
	for light: LightSource in lights: # 常亮灯多时仍为短时演出保留真实投影。
		if _emitters.size() >= Ground.LIGHT_GRID.x * Ground.LIGHT_GRID.y:
			return
		if light.shadow_priority == priority and light.height > 0.0 and is_instance_valid(light.ground_anchor):
			light.shadow_slot = _emitters.size()
			_emitters.append(light)

## 用 [param projection] 和 [param bounds] 提交原位身体批次和逐顶点地面批次。
func _submit(projection: Transform2D, bounds: Rect2) -> bool:
	_ground.begin()
	var receivers: MultiMesh = body_clear.multimesh # 恢复身体所占像素的原始灯光。
	var count := 0 # 提交到低分辨率光场的原位实例数。
	for caster: Caster in _active: # 刚分配而尚未绘制的格不参与当前帧。
		if caster.generation < 0 or not caster.pose_bounds.has_area():
			continue
		var foot: Vector2 = caster.foot.global_position # 即使姿态缓存尚未刷新，脚点仍跟随实际移动。
		var tile: Vector2i = Atlas.tile_coords(caster.tile) # 两个批次采样同一格。
		var shape: Rect2 = caster.pose_bounds # 只描述源图集的裁切位置。
		var native := Transform2D(0.0, shape.size * 0.5, 0.0, foot + shape.get_center()) # 身体的未变形位置。
		var receiver: Transform2D = projection * native # 转到实际相机和光场分辨率。
		if bounds.intersects(receiver * Rect2(-1.0, -1.0, 2.0, 2.0)):
			receivers.set_instance_transform_2d(count, receiver)
			receivers.set_instance_custom_data(count, Color(tile.x / 255.0, tile.y / 255.0, 1.0, 1.0))
			count += 1
		var opacity: float = shadow_opacity * smoothstep(0.0, 1.0, caster.handoff) # 只在实际主灯切换时淡化。
		if opacity > 0.0:
			_ground.submit(foot, shape, tile, caster.reference_height, caster.body_height, caster.primary, opacity,
				max_shadow_world_extent)
	_ground.flush()
	var drawn: bool = _ground.count > 0 # 无影帧不读取旧灯格或复制身体背景。
	receivers.visible_instance_count = count if drawn else 0
	_mask.render_target_update_mode = SubViewport.UPDATE_ONCE if drawn else SubViewport.UPDATE_DISABLED
	return drawn
