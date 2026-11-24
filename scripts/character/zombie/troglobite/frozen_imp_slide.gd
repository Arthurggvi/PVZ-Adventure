## 执行单块冰壳已经算好的位移，并沿途检查友方屏障与植物。
extends Node2D
class_name FrozenImpSlide

## 冰块碾压检测带的世界宽度，单位为像素。
const CONTACT_WIDTH: float = 52.0
## 植物与友方屏障的碰撞层。
const PLANT_MASK: int = 2
## 场景子节点归属的雪人小鬼；走原生坡面接口更新脚点。
@onready var _zombie: Zombie000Base = owner as Zombie000Base
## 复用现有屏障优先级和拦截资格，仅供即时查询。
@onready var _detector: DetectComponent = $SlideDetect
## 本冰块独占的扫掠形状节点。
@onready var _collider: CollisionShape2D = $SlideDetect/Area2d/CollisionShape2D
## 每次扫掠按位移改变矩形宽度，场景为每个实例分配独立形状。
@onready var _shape: RectangleShape2D = _collider.shape as RectangleShape2D
## 当前一次推行已经撞过的植物实例，避免幸存特例逐步重复受击。
var _contacted: Dictionary[int, bool] = {}

## 检测区域关闭监听；整链推行逐步主动查询。
func _ready() -> void:
	_detector.disable_component(ComponentNormBase.E_IsEnableFactor.Default)

## 开始下一次推行的碾压记录。
func begin_sweep() -> void:
	_contacted.clear()

## 尝试提交 [param step] 的世界横移。[param is_frozen] 在每次伤害回调后核对冰壳资格。
func advance(step: float, is_frozen: Callable) -> void:
	if not _sweep_clear(step, is_frozen):
		return
	var row: CanvasItem = _zombie.get_parent() as CanvasItem # 坡面接口以父节点局部步长为输入。
	var step_local: Vector2 = row.get_global_transform().affine_inverse().basis_xform(Vector2(-step, 0.0)) # 沿用原生左移为正规则。
	_zombie.global_position.x += step
	_zombie.move_component.move_y_correct(step_local.x)
	_zombie.move_component.update_previous_ground_global_x()

## [param step] 是尚未提交的世界横移。[param is_frozen] 判断本块是否仍能推行。
## 屏障挡住本步；破壳或死亡则停止提交本步及位置更新。
func _sweep_clear(step: float, is_frozen: Callable) -> bool:
	_shape.size = Vector2(CONTACT_WIDTH + absf(step), 8.0)
	_collider.global_transform = Transform2D(0.0, Vector2(_zombie.global_position.x + step * 0.5,
		_detector.global_position.y - 40.0))
	var areas: Array[Area2D] = CombatExplosion.query_collider(_collider, PLANT_MASK) # 同步查询完整的接触带。
	_detector.enemy_can_be_attacked = null
	_detector.judge_enemy_in_areas(areas)
	if _detector.enemy_can_be_attacked is FriendlyBattleBarrier:
		return false
	var from_x: float = _zombie.global_position.x # 未提交横移的起点。
	var to_x: float = from_x + step # 本子步的目标终点。
	for cell: PlantCell in Global.main_game.board.row_cells(_zombie.lane): # 实际种植格包括稀疏布局和移动平台。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion():
			continue
		var bounds: Rect2 = cell.get_global_rect() # 低矮和伴生植物仍从实际经过的格读取。
		if bounds.position.x > maxf(from_x, to_x) or bounds.end.x < minf(from_x, to_x):
			continue
		for plant: Plant000Base in cell.living_plants(): # 每层独立处理；冻结植物略过。
			_crush_plant(plant)
			if not is_frozen.is_valid() or not bool(is_frozen.call()):
				return false
	return true

## [param plant] 来自经过格的存活快照；上一次伤害可能已移除它。
func _crush_plant(plant: Plant000Base) -> void:
	if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion() or plant.is_cold_frozen():
		return
	var identity: int = plant.get_instance_id() # 同一次推行的重复扫段按实际植株去重。
	if _contacted.has(identity):
		plant.show_crush_contact()
		return
	_contacted[identity] = true
	plant.be_flattened_from_enemy(_zombie)
