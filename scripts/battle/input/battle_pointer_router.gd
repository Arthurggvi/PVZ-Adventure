## 战场私有的指针前置入口；环境映射与普通输入共用同一次过滤，不保存全局游戏状态。
extends Node

## 视口只保存当前战场路由的弱引用，场景离开后解除。
const ROUTER_KEY := &"battle_pointer_router"
## 标记已由本实例处理的事件，环境复制转发时不重复解释。
const ROUTED_KEY := &"battle_pointer_routed_by"
## 取消既有 GUI 按压时放行合成的 canceled 事件，避免被当前手势再次吞掉。
const CANCEL_KEY := &"battle_pointer_cancel"
## 当前输入所属视口，用于在离树时撤销唯一入口。
var _input_viewport: Viewport

## 路由随战斗创建；始终接收释放事件，暂停期间也能清理已接管的指针。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_input_viewport = get_viewport()
	_input_viewport.set_meta(ROUTER_KEY, weakref(self))

## 无环境映射时的正常入口；[param event] 被前置过滤消费后不再交给 GUI 或战场。
func _input(event: InputEvent) -> void:
	if filter_before_mapping(get_viewport(), event):
		get_viewport().set_input_as_handled()

## 让 [param viewport] 的战场路由先处理物理 [param event]；返回是否应停止继续分发。
## 环境层必须在改变坐标或丢弃原始触点前调用；事件副本保留处理标记。
static func filter_before_mapping(viewport: Viewport, event: InputEvent) -> bool:
	if event.has_meta(CANCEL_KEY) or not viewport.has_meta(ROUTER_KEY):
		return false
	var reference: WeakRef = viewport.get_meta(ROUTER_KEY) as WeakRef # 不延长战斗节点寿命。
	var router: Node = reference.get_ref() as Node if reference != null else null # 当前仍存活的路由。
	if not is_instance_valid(router) or router.is_queued_for_deletion():
		return false
	var identity: int = router.get_instance_id() # 防止跨场景重用事件时误认成已处理。
	if int(event.get_meta(ROUTED_KEY, 0)) == identity:
		return false
	event.set_meta(ROUTED_KEY, identity)
	return router._filter_pointer(event)

## 子类解释 [param _event]，默认不接管任何输入。
func _filter_pointer(_event: InputEvent) -> bool:
	return false

## 只撤销本实例登记的入口，不能清掉后续战场已安装的路由。
func _exit_tree() -> void:
	if not is_instance_valid(_input_viewport) or not _input_viewport.has_meta(ROUTER_KEY):
		return
	var reference: WeakRef = _input_viewport.get_meta(ROUTER_KEY) as WeakRef # 与注册时的弱引用核对所有者。
	if reference != null and reference.get_ref() == self:
		_input_viewport.remove_meta(ROUTER_KEY)
