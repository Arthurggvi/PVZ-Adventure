## 创伤尖刺跟随真实动画部件，最多四个渲染项；无逐帧 GDScript 更新。
extends Node

## 每增加20层创伤可显露一根尖刺。
const STACKS_PER_SPIKE: int = 20
## 每只僵尸最多显示12根，创伤伤害仍保留全部实际层数。
const MAX_SPIKES: int = 12
## 每只僵尸最多选择四个独立动画部件。
const MAX_ANCHORS: int = 4

## 固定在某个真实动画部件上的批量绘制项。
class Anchor:
	## 部件的本地坐标包含动画与装备翻转。
	var node: Node2D
	## 第一次击中时采样的精灵区域。
	var rect: Rect2
	## 多根尖刺共用的底层画布项。
	var item: RID

## 这一只僵尸的固定随机序列，与正式战斗的随机流无关。
var _random := RandomNumberGenerator.new()
## 可用身体部件及其绘制项。
var _anchors: Array[Anchor] = []
## 已经显露的尖刺数。
var _shown: int = 0

## 从 [param target] 的活动部件中随机选择不超过四个锚点。
func setup(target: Zombie000Base) -> void:
	_random.seed = target.get_instance_id() * 6271
	var candidates: Array[Sprite2D] = [] # 只从确实有体积且当前可见的部件选取。
	for child: Node in target.body.find_children("*", "Sprite2D", true, false):
		var sprite := child as Sprite2D # 身体动画原生分件或备用静态轮廓。
		if not sprite.is_visible_in_tree() or sprite.texture == null:
			continue
		var size: Vector2 = sprite.get_rect().size * sprite.global_scale.abs() # 用当前渲染尺寸排除细小装饰。
		if size.x >= 12.0 and size.y >= 13.0:
			candidates.append(sprite)
	while not candidates.is_empty() and _anchors.size() < MAX_ANCHORS:
		var sprite: Sprite2D = candidates.pop_at(_random.randi_range(0, candidates.size() - 1)) # 不依赖全局随机数。
		_add_anchor(sprite, sprite.get_rect())
	if _anchors.is_empty():
		_add_anchor(target.body, Rect2(-13.0, -74.0, 28.0, 46.0))

## 为 [param part] 登记 [param rect]；真正出现尖刺时才创建渲染项。
func _add_anchor(part: Node2D, rect: Rect2) -> void:
	var anchor := Anchor.new() # 坐标仍在原部件局部空间。
	anchor.node = part
	anchor.rect = rect
	_anchors.append(anchor)

## 将 [param stacks] 对应的新增尖刺一次性加入锚点渲染项。
func show_stacks(stacks: int) -> void:
	var count: int = clampi(ceili(float(stacks) / STACKS_PER_SPIKE), 0, MAX_SPIKES) # 逻辑层数不受渲染上限约束。
	while _shown < count:
		var anchor: Anchor = _anchors[_shown % _anchors.size()] # 让尖刺先分布再在同部件叠加。
		_shown += 1
		if is_instance_valid(anchor.node):
			_draw_quill(anchor)

## 在 [param anchor] 内随机挑选着刺点、朝向、长度和紫色。
func _draw_quill(anchor: Anchor) -> void:
	if not anchor.item.is_valid():
		anchor.item = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(anchor.item, anchor.node.get_canvas_item())
	var side: float = -1.0 if _random.randf() < 0.5 else 1.0 # 部件两侧都可以长刺。
	# 着刺点仍落在部件内部，尖端越过轮廓。
	var middle: Vector2 = anchor.rect.position + anchor.rect.size * Vector2(
		0.5 + side * _random.randf_range(0.08, 0.25), _random.randf_range(0.24, 0.74))
	var heading: Vector2 = Vector2(side * _random.randf_range(0.45, 1.0), _random.randf_range(-1.0, 0.25)).normalized() # 大多向外倾斜。
	var along: Vector2 = heading * _random.randf_range(12.0, 22.0) / anchor.node.global_scale.abs().max(Vector2(0.1, 0.1)) # 尺寸以世界像素计。
	var sidewards: Vector2 = heading.orthogonal() * _random.randf_range(2.1, 3.9) / anchor.node.global_scale.abs().max(Vector2(0.1, 0.1)) # 梯度尖部两翼。
	var purple: Color = Color("ac4fed").lerp(Color("e177ff"), _random.randf()) # 几种深浅与刺形可同时叠加。
	RenderingServer.canvas_item_add_polygon(anchor.item, PackedVector2Array([
		middle - sidewards * 1.2, middle + along * 1.04, middle + sidewards * 1.2,
		middle - along * 0.21]), PackedColorArray([Color("36194d")]))
	RenderingServer.canvas_item_add_polygon(anchor.item, PackedVector2Array([
		middle - sidewards * 0.78, middle + along, middle + sidewards * 0.72,
		middle - along * 0.13]), PackedColorArray([purple, Color("fce1ff"), Color("7533be"), Color("5b288c")]))

## [param what] 为离场通知；原分件可能已释放，仍须回收独立 RID。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for anchor: Anchor in _anchors: # 只释放真实创建过的绘制项。
			if anchor.item.is_valid():
				RenderingServer.free_rid(anchor.item)
