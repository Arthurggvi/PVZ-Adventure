extends RefCounted
## 注册表资源只由活跃战斗持有；战外请求由实际消费者和 Godot 自身资源缓存负责。

## 当前战斗实例编号，零表示没有强引用租约。
var _owner_id: int = 0
## 本局按路径复用的原生资源；不持有任何角色节点。
var _resources: Dictionary[String, Resource] = {}

## [param owner] 是当前战斗根节点，战外传 null；[param path] 是正式注册路径。
## 返回 Godot 原生缓存的资源；战斗离树后只释放本租约，不干涉仍持有资源的实例。
func resolve(owner: Node, path: String) -> Resource:
	var owned: bool = is_instance_valid(owner) and owner.is_inside_tree() and not owner.is_queued_for_deletion() # 只接受活跃战斗。
	if owned:
		_bind_owner(owner)
		if _resources.has(path):
			return _resources[path]
	var resource: Resource = ResourceLoader.load(path) # 复用 ResourceLoader 已有引用。
	if owned and resource != null:
		_resources[path] = resource
	return resource

## [param owner] 当前战斗；[param resource] 为已完成准备的注册资源，不重新读盘。
func retain(owner: Node, resource: Resource) -> void:
	if not is_instance_valid(owner) or not owner.is_inside_tree() or resource == null or resource.resource_path.is_empty():
		return
	_bind_owner(owner)
	_resources[resource.resource_path] = resource

## [param owner] 绑定唯一的战斗身份，退出时撤销本局租约。
func _bind_owner(owner: Node) -> void:
	var id: int = owner.get_instance_id() # 重开时区分旧、新战斗。
	if _owner_id != id:
		_resources.clear()
		_owner_id = id
		owner.tree_exiting.connect(_release.bind(id), CONNECT_ONE_SHOT)

## [param id] 是离树的原战斗编号；旧信号不得释放新战斗的资源。
func _release(id: int) -> void:
	if id == _owner_id:
		_resources.clear()
		_owner_id = 0
