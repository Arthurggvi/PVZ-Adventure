## 同一单位面片批绘火焰、烟、火星和真实爆心的短压强波。近场暖光在战斗行下层。
extends RefCounted

## 固定槽位负责各物质的世界运动和形态。
const Particle := preload("res://scripts/adventure/garden_airship/garden_airship_blast_particle.gd")
## 八个浮点为 2D 矩阵，随后四个为颜色、四个为材质及形变。
const STRIDE: int = 16
## 正式战斗画布中高于五条僵尸行和飞机；HUD 使用独立 CanvasLayer。
const PRODUCT_Z: int = 290
## 地板上方与战斗行下方的局部暖光。无需全屏纹理采样。
const GLOW_Z: int = -2
## 暖光只用于完整主爆，超过此并发只省略补光。
const GLOW_CAPACITY: int = 12
## 现有正片和烟图均是旧演出已使用的资源。
const CORE := preload("res://assets/image/particles/BossExplosion1.png")
## 透明边缘带锯齿手绘轮廓的白色火团。
const FLAME := preload("res://assets/image/particles/BossExplosion2.png")
## 爆开瞬间的不规则射线。
const RAYS := preload("res://assets/image/particles/BossExplosion3.png")
## 原仲裁者 4×2 烟图。
const SMOKE := preload("res://assets/adventure/zombies/arbiter_x/smoke_atlas.png")
## 主批次与局部补光共享的一个兼容渲染材质。
const SHADER := preload("res://shaders/adventure/wonderland/garden_airship_blast_particles.gdshader")

## 受风产物及压强波批次。
var _products: MultiMesh
## 低于战斗行的暖光面片批次。
var _glows: MultiMesh
## 主批次裁剪后顺序写入的预分配实例缓冲。
var _product_buffer := PackedFloat32Array()
## 同局暖光预分配实例缓冲。
var _glow_buffer := PackedFloat32Array()
## 当前发布的可见产物数量。
var _product_count: int = 0
## 当前发布的局部暖光数量。
var _glow_count: int = 0

## 在同一 [param parent] 战斗画布建两批面片，共用纹理、材质和四边形。
## [param capacity] 是主批次最大实例数，槽位和资源在整场战斗里复用。
func bind(parent: Node2D, capacity: int) -> void:
	var quad := QuadMesh.new() # 单位宽高，世界形状由各实例矩阵控制。
	quad.size = Vector2.ONE
	var material := ShaderMaterial.new() # 只建一次，不按粒子生成或复制。
	material.shader = SHADER
	material.set_shader_parameter(&"hot_core", CORE)
	material.set_shader_parameter(&"flame_lobe", FLAME)
	material.set_shader_parameter(&"rays", RAYS)
	material.set_shader_parameter(&"smoke_atlas", SMOKE)
	_products = _add_batch(parent, quad, material, capacity, PRODUCT_Z, &"BlastProducts")
	_glows = _add_batch(parent, quad, material, GLOW_CAPACITY, GLOW_Z, &"BlastGlow")
	_product_buffer.resize(capacity * STRIDE)
	_glow_buffer.resize(GLOW_CAPACITY * STRIDE)

## 按 [param view] 的实际世界可见范围裁剪 [param slots] 前 [param count] 个活跃物。
## [param from_world] 只在提交时把真实世界变换换成批次局部变换。
func publish(slots: Array[Particle], count: int, view: Rect2, from_world: Transform2D) -> void:
	_product_count = 0
	_glow_count = 0
	for index: int in count: # 把烟和地板暖光放在亮火团后面。
		var particle: Particle = slots[index] # 只有活跃前缀，不遍历空闲槽。
		if particle.kind <= Particle.Kind.SMOKE:
			_submit(particle, view, from_world)
	for index: int in range(count - 1, -1, -1): # 每个爆点的短热核绘在自身火团之上。
		var particle: Particle = slots[index] # 非烟实例走同一个主批次。
		if particle.kind > Particle.Kind.SMOKE:
			_submit(particle, view, from_world)
	if _product_count > 0:
		_products.buffer = _product_buffer
	if _glow_count > 0:
		_glows.buffer = _glow_buffer
	_products.visible_instance_count = _product_count
	_glows.visible_instance_count = _glow_count

## 返回裁剪后真实提交的面片数，包括有限的地板暖光。
func visible_count() -> int:
	return _product_count + _glow_count

## 将 [param particle] 的世界面片与 [param view] 求交，仅提交可见部分。
## [param from_world] 是各批共享的逆世界矩阵。
func _submit(particle: Particle, view: Rect2, from_world: Transform2D) -> void:
	var tint: Color = particle.draw_tint() # 透明阶段不会占用 GPU 几何。
	if tint.a < 0.009:
		return
	var pose: Transform2D = particle.draw_transform() # 含独立的旋转、形变与可见中心。
	var half: Vector2 = (pose.x.abs() + pose.y.abs()) * 0.5 # 旋转后的世界包围盒半径。
	if not view.intersects(Rect2(pose.origin - half, half * 2.0)):
		return
	if particle.kind == Particle.Kind.GLOW:
		if _glow_count < GLOW_CAPACITY:
			_write(_glow_buffer, _glow_count, from_world * pose, tint, particle)
			_glow_count += 1
		return
	_write(_product_buffer, _product_count, from_world * pose, tint, particle)
	_product_count += 1

## 向 [param buffer] 的 [param index] 写入局部 [param pose]、[param tint] 与 [param particle] 的形态。
func _write(buffer: PackedFloat32Array, index: int, pose: Transform2D, tint: Color,
		particle: Particle) -> void:
	var offset: int = index * STRIDE # 同一面片的变换、颜色、局部参数连续存放。
	buffer[offset] = pose.x.x
	buffer[offset + 1] = pose.y.x
	buffer[offset + 3] = pose.origin.x
	buffer[offset + 4] = pose.x.y
	buffer[offset + 5] = pose.y.y
	buffer[offset + 7] = pose.origin.y
	buffer[offset + 8] = tint.r
	buffer[offset + 9] = tint.g
	buffer[offset + 10] = tint.b
	buffer[offset + 11] = tint.a
	buffer[offset + 12] = float(particle.kind) / float(Particle.Kind.METAL)
	buffer[offset + 13] = particle.phase
	buffer[offset + 14] = particle.stretch() if particle.kind == Particle.Kind.FLAME else 0.0
	buffer[offset + 15] = particle.age / particle.life

## 在 [param parent] 建立名为 [param label] 的固定批次，使用共享 [param quad] 和 [param material]。
## [param count] 为最大实例数，[param depth] 为战斗画布上的绝对 z。
func _add_batch(parent: Node2D, quad: QuadMesh, material: ShaderMaterial, count: int,
		depth: int, label: StringName) -> MultiMesh:
	var batch := MultiMesh.new() # 未活跃时不提交任何实例。
	batch.transform_format = MultiMesh.TRANSFORM_2D
	batch.use_colors = true
	batch.use_custom_data = true
	batch.mesh = quad
	batch.instance_count = count
	batch.visible_instance_count = 0
	var layer := MultiMeshInstance2D.new() # 此处是同一画布相对绘制深度，不新建 CanvasLayer。
	layer.name = label
	layer.z_as_relative = false
	layer.z_index = depth
	layer.multimesh = batch
	layer.material = material
	parent.add_child(layer)
	return batch
