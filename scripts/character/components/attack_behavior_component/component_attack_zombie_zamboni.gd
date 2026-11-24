## 造冰车逐帧检查车头覆盖的格子，碾压同一格的植物和承载物。
extends AttackComponentBase
class_name AttackComponentZombieZamboni

## 原版在爆炸植物和主动触发的倭瓜面前继续行驶。
const CRUSH_EXEMPT := [
	CharacterRegistry.PlantType.P003CherryBomb, CharacterRegistry.PlantType.P018Squash,
	CharacterRegistry.PlantType.P020TangleKelp, CharacterRegistry.PlantType.P021Jalapeno,
	CharacterRegistry.PlantType.P028Blover,
]

## 车头顶住障碍时的持续挤压间隔，单位为游戏秒。
const BARRIER_IMPACT_INTERVAL: float = 1.0
## 车头撞击与挤压障碍时扣除的共享血量。
const BARRIER_IMPACT_DAMAGE: int = 1800
## 当前接触的屏障 ID；实体释放后仍可识别并撤销停车来源。
var _wall_id: int = 0
## 距离下次挤压所剩的游戏秒数。
var _wall_wait: float = 0.0
## 上次检测后仍在车头范围内的存活植株。
var _previous_crush_contacts: Dictionary[int, bool] = {}
## 本次检测中扛住碾压的植株，两份表轮换复用。
var _crush_contacts: Dictionary[int, bool] = {}

## 车头的碰撞包含不会被僵尸主动攻击的植物。
func _ready() -> void:
	super()
	detect_component.detects_hidden_plant_contacts = true

## [param delta] 推进接触后的重复挤压；普通植物沿用原生碾压判定。
func _physics_process(delta: float) -> void:
	if not is_enabling or owner.is_death or owner.is_action_suspended():
		_set_wall(null)
		return
	var reusable: Dictionary[int, bool] = _previous_crush_contacts # 某株分离后，下次接触允许重新结算。
	_previous_crush_contacts = _crush_contacts
	_crush_contacts = reusable
	_crush_contacts.clear()
	# targets 是车头范围内可攻击的角色；路障拦截后才允许碰到后方的植物。
	var targets: Array[Character000Base] = detect_component.get_all_enemy_can_be_attacked()
	for target: Character000Base in targets: # 屏障先消耗共享血池，而不是被碾压规则瞬间处决。
		if target is FriendlyBattleBarrier:
			_set_wall(target)
			_wall_wait -= delta
			if _wall_wait <= 0.0:
				_wall_wait = BARRIER_IMPACT_INTERVAL
				target.be_zombie_eat(BARRIER_IMPACT_DAMAGE, owner)
			return
	_set_wall(null)
	# target 是一次重叠查询得到的候选。
	for target: Character000Base in targets:
		if target is Plant022Caltrop or target is Plant047SpikeRock:
			target.be_flattened_from_enemy(owner)
			return
	# target 为本次撞到的角色，植物的外层和底座随格一起压扁。
	for target: Character000Base in targets:
		if owner.is_death:
			return
		if is_instance_valid(target) and not target.is_death and target is Plant000Base \
				and not target.is_queued_for_deletion() and _can_crush(target):
			_crush_cell(target.plant_cell)
	if is_instance_valid(detect_component.brain) and not detect_component.brain.is_death:
		detect_component.brain.be_flattened()

## [param wall] 是此刻真正挡在车头的路障；传空时恢复这一来源的位移。
func _set_wall(wall: FriendlyBattleBarrier) -> void:
	var id: int = wall.get_instance_id() if wall != null else 0 # 空接触的哨兵值。
	if id == _wall_id:
		return
	_wall_id = id
	_wall_wait = 0.0
	owner.move_component.set_move_rate_source(get_instance_id(), 1.0 if id == 0 else 0.0)

## [param plant] 为车头覆盖的植物，休眠的冰菇和毁灭菇也可被压扁。
func _can_crush(plant: Plant000Base) -> bool:
	if plant.plant_type in [CharacterRegistry.PlantType.P015IceShroom, CharacterRegistry.PlantType.P016DoomShroom]:
		return plant.is_sleeping
	return plant.plant_type not in CRUSH_EXEMPT

## [param cell] 为受碾压的格子，压扁后植物会自行清理占位。
func _crush_cell(cell: PlantCell) -> void:
	if not is_instance_valid(cell):
		return
	# plant 是本格当前的存活实体，包含不占种植位的伴生。
	for plant: Plant000Base in cell.living_plants():
		if owner.is_death:
			return
		if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion() or plant.is_cold_frozen():
			continue
		var identity: int = plant.get_instance_id() # 每次重叠按实际植株去重，不受多层受击盒影响。
		if _crush_contacts.has(identity):
			continue
		if _previous_crush_contacts.has(identity):
			_crush_contacts[identity] = true
			plant.show_crush_contact()
			continue
		plant.be_flattened_from_enemy(owner)
		if is_instance_valid(plant) and not plant.is_death and not plant.is_queued_for_deletion():
			_crush_contacts[identity] = true

## 车头的检测信号不切换普通僵尸的停步啃食状态。
func attack_start() -> void:
	pass

## 驶离目标时继续行驶。
func attack_end() -> void:
	pass

## [param _speed_product] 为角色速度倍率，车轮重叠判定本身没有攻击间隔。
func owner_update_speed(_speed_product: float) -> void:
	pass
