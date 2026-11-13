## 战斗宿主拥有的有界视觉对象池；离树缓存只存在于本场，销毁宿主会彻底释放它们。
extends Node
class_name RepeaterVisualPool

## 一个场景每类最多缓存24个短命视觉节点。
const LIMIT: int = 24
## 节点固定名称，避免每次命中新建独立池。
const NODE_NAME: StringName = &"RepeaterVisualPool"

## 普通弹体命中与吸血链的离树闲置节点。
var _impacts: Array[Node2D] = []
## 冥弹黑白裂隙的离树闲置节点。
var _hades: Array[Node2D] = []

## 在 [param host] 下面取得唯一池；即使中途战斗结束也与场景共同销毁。
static func under(host: Node) -> RepeaterVisualPool:
	if not is_instance_valid(host) or host.is_queued_for_deletion():
		return null
	var previous: RepeaterVisualPool = host.get_node_or_null(NodePath(NODE_NAME)) as RepeaterVisualPool
	if previous != null:
		return previous
	var pool := RepeaterVisualPool.new()
	pool.name = NODE_NAME
	host.add_child(pool)
	pool.set_process(false)
	return pool

## 取回一个不在场景树中的视觉节点；没有缓存时返回空，调用方按正式类型创建。
func acquire(kind: StringName) -> Node2D:
	var cache: Array[Node2D] = _hades if kind == &"hades" else _impacts
	while not cache.is_empty():
		var node: Node2D = cache.pop_back()
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.show()
			node.set_process(true)
			return node
	return null

## 回收先移除原宿主，触发预算撤销，再把无场景引用的节点放回缓存。
func release(kind: StringName, node: Node2D) -> void:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.hide()
	node.set_process(false)
	var cache: Array[Node2D] = _hades if kind == &"hades" else _impacts
	if cache.size() < LIMIT and not is_queued_for_deletion():
		cache.append(node)
	else:
		node.free()

## 正式战场销毁时，所有离树缓存节点都会释放；不留下进程级CanvasItem。
func _exit_tree() -> void:
	for cache: Array[Node2D] in [_impacts, _hades]:
		for node: Node2D in cache:
			if is_instance_valid(node):
				node.free()
		cache.clear()

## 用于验收场景结束后的资源数量审计。
func sizes() -> Vector2i:
	return Vector2i(_impacts.size(), _hades.size())
