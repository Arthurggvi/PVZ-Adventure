## 仲裁者-X型独立碾压攻击：三条有效行、单次接触、每秒300点。
## 机体移动和攻击状态互不覆盖，受击、被冻结植物由原生命组件结算。
extends AttackComponentBase
class_name AttackComponentZombieArbiterX

## 相邻碾压结算的最小动作秒数。
const TICK: float = 0.20
## 每秒300点对应单次结算60点，普通打击不跳过原植物护甲。
const DAMAGE: int = 60
## 机头前方的接触长度，随棋盘实际格宽缩放。
const FRONT_RATIO: float = 0.75

## 所属战斗机，不自行记录生命或战斗行。
var _plane: Zombie000Base
## 距离下次结算的动作秒数。
var _elapsed: float = 0.0

## 预览场景不扫描植物，正式进入战场后启用。
func _ready() -> void:
	super()
	set_physics_process(false)

## [param plane] 是同一机体，双向信号由 Zombie000Base 统一完成。
func activate(plane: Zombie000Base) -> void:
	_plane = plane
	set_physics_process(true)

## 按实际本机所在行和上下相邻行进行攻击，不用固定屏幕坐标推测行号。
func _physics_process(delta: float) -> void:
	if not is_enabling or not is_instance_valid(_plane) or _plane.is_death \
			or _plane.is_queued_for_deletion() or _plane.is_hypno or _plane.is_action_suspended():
		return
	_elapsed += delta * _plane.action_rate()
	if _elapsed < TICK:
		return
	_elapsed = fmod(_elapsed, TICK)
	var game: MainGameManager = Global.main_game
	if not is_instance_valid(game) or not game.is_ancestor_of(_plane) or game.board == null:
		return
	var width: float = game.board.cell_width_at(_plane.global_position, _plane.lane)
	if width <= 0.0:
		return
	var nose: float = _plane.global_position.x - width * 0.42
	for row: int in range(maxi(0, _plane.lane - 1), mini(game.board.extent.x, _plane.lane + 2)):
		for cell: PlantCell in game.board.row_cells(row):
			for plant: Plant000Base in cell.living_plants():
				if is_instance_valid(plant) and not plant.is_death and not plant.is_queued_for_deletion() \
						and absf(plant.global_position.x - nose) <= width * FRONT_RATIO:
					_hit_plant(plant)

## 仅在真实死亡时触发原本体的压扁动画，不向植物额外发出二次死亡信号。
func _hit_plant(plant: Plant000Base) -> void:
	if plant.is_cold_frozen() or _plane.is_death:
		return
	var health: HpComponent = plant.hp_component
	var flattened: Callable = _on_crushed.bind(plant)
	health.before_death.connect(flattened, CONNECT_ONE_SHOT)
	plant.be_zombie_eat(DAMAGE, _plane)
	if is_instance_valid(plant) and not plant.is_death:
		plant.show_crush_contact()
	if is_instance_valid(health) and health.before_death.is_connected(flattened):
		health.before_death.disconnect(flattened)

## 原有生命组件确认死亡后的单次压扁表现。
func _on_crushed(_cause: CombatHitScope.DeathCause, plant: Plant000Base) -> void:
	if is_instance_valid(plant) and plant.is_inside_tree() and is_instance_valid(plant.body):
		plant.body.be_flattened_body()

## 被击毁、风吹离场与波次清场时停止接触检查。
func finish_life() -> void:
	set_physics_process(false)

## 载具接触植物时不会停止推进或进入咬食状态。
func attack_start() -> void:
	pass

## 离开目标不触发移动锁或额外攻击。
func attack_end() -> void:
	pass

## [param _speed_product] 移速由移动组件负责，本组件只读取合成行动速度。
func owner_update_speed(_speed_product: float) -> void:
	pass
