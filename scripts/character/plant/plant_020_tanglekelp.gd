extends Plant000Base
class_name Plant020Tanglekelp

## 从抓取开始到植物格冒水花的初代时点，单位秒。
const PLANT_SPLASH_AT: float = 0.8
## 原生检测区内尚无合法水格目标时，按此间隔复核脚点，单位秒。
const WATER_ENTRY_RECHECK_SECONDS: float = 0.1

## 仅普通僵尸使用的拖拽表现与处决组件。
@onready var grap_component: GrapComponent = $GrapComponent
## 查找当前仍处于受击范围内的目标。
@onready var detect_component: DetectComponent = $DetectComponent
## 僵王不会被拖入水中，改为一次穿透伤害；命中后海草仍消耗自身。
@export_range(0, 10000, 1, "or_greater") var boss_attack_value: int = 1800
## 海草是一次性攻击，防止等待动画期间重复响应索敌信号。
var _is_attacking: bool = false
## 本株从实际出战卡冻结的转职事件，原版海草为空。
var _promotions: Dictionary[String, Dictionary] = {}
## 首次准备时即锁定正常放置或寄生，后续复核不得重新选择。
var _placement_prepared: bool = false
## 寄生宿主的弱引用；空值表示本次为普通种植。
var _parasite_host: WeakRef
## 已安排一次水域复核；同一重叠期间不会重复创建计时器。
var _water_entry_recheck_pending: bool = false

## [param events] 来自已经验证的本株转职路线；入树前冻结后不再读取库存。
func configure_promotions(events: Array[Dictionary]) -> void:
	for event: Dictionary in events: # 同一次拖拽或寄生只读取这份配置。
		_promotions[String(event.kind)] = event.duplicate(true)

## [param origin] 为新放置时冻结实际宿主；提交前只验证原目标是否仍然可用。
func prepare_placement_action(origin: PlantCell.PlacementOrigin = PlantCell.PlacementOrigin.Player) -> bool:
	if not _promotions.has("tanglekelp_parasite") or origin not in [PlantCell.PlacementOrigin.Player, PlantCell.PlacementOrigin.Spawned]:
		return true
	var host: Plant000Base = ResourcePlantConditionTanglekelp.parasite_host(plant_cell) # 读取当前同一格的实际可选目标。
	if _placement_prepared:
		if _parasite_host == null:
			return host == null
		return host != null and _parasite_host.get_ref() == host
	_placement_prepared = true
	_parasite_host = weakref(host) if host != null else null
	return true

## 叠种完成即转移缠绕部件；延后释放临时槽，保证格子的创建通知先于消耗通知。
func commit_placement_action() -> void:
	if _parasite_host == null:
		return
	var host := _parasite_host.get_ref() as Plant000Base # 提交只使用准备时锁定的对象。
	if host == null:
		return
	AdventureTanglekelpParasite.attach(host, grap_component, _promotions)
	death_recording_enabled = false
	is_can_death_language = false
	hide()
	character_death.call_deferred()

## 拖拽开始后要在原水域完成下沉动作；寄生用的临时节点无法被手套移走。
func can_relocate() -> bool:
	return not _is_attacking and _parasite_host == null

## 玩家在 [param cell] 提交与 [param profile] 一致的海草后，按正常可用格铺开一次。
static func expand_player_placement(cell: PlantCell, profile: PlantSpawnProfile) -> void:
	if not is_instance_valid(cell) or profile == null \
			or not profile.matches_plant_type(CharacterRegistry.PlantType.P020TangleKelp):
		return
	for plant: Plant000Base in cell.living_plants(): # 主格可能是正常落点，也可能是寄生消费前的临时层。
		var source := plant as Plant020Tanglekelp # 其他同格植物不能触发本卡扩种。
		if source == null or source.plant_spawn_profile != profile or not source._promotions.has("tanglekelp_spread"):
			continue
		var battle: RepeaterShotContext = RepeaterShotContext.from_plant(source) # 技能子株只允许在本次实际战斗创建。
		if battle == null:
			return
		for target: PlantCell in AdventureTanglekelpGrabs.neighborhood(cell): # 中心已成功放置，子株沿用本卡冻结的完整能力。
			if target != cell and battle.is_active():
				target.create_plant(CharacterRegistry.PlantType.P020TangleKelp, false, true, false, false,
					profile, PlantCell.PlacementOrigin.Spawned)
		return

## 寄生用途的临时节点不会参与原生索敌或代替宿主受击。
func ready_norm_signal_connect() -> void:
	super()
	if _parasite_host != null:
		detect_component.disable_component(ComponentNormBase.E_IsEnableFactor.Attack)
		hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Attack)
	else:
		detect_component.signal_can_attack.connect(start_grap_zombie)

## 植物、攻击和检测组件必须仍处于可出手的状态。
func _can_start_grab() -> bool:
	return is_inside_tree() and not is_death and not is_queued_for_deletion() \
		and not _is_attacking and detect_component.is_enabling

## 原生索敌触发一次海草攻击；恶鬼在同一发起点改用水域九宫格。
func start_grap_zombie() -> void:
	if not _can_start_grab():
		return
	var enemy: Character000Base = detect_component.update_first_enemy() # 确认当前仍能命中原生目标。
	if not (enemy is Zombie000Base or enemy is ZB000Base or enemy is EnemyStructureBase):
		return
	if enemy is Zombie000Base and enemy.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsDraggedUnder:
		return
	var grabs: AdventureTanglekelpGrabs = null # 失效转职和原版海草仍用原生单体抓取。
	if not _promotions.is_empty() and not has_node(NodePath(AdventurePlantNullification.NODE_NAME)):
		grabs = AdventureTanglekelpGrabs.capture(self, _promotions)
	var targets: Array[Zombie000Base] = [] # 同一攻击时点冻结真实目标，不因死亡等信号回头找其他敌人。
	if grabs != null and _promotions.has("tanglekelp_evil_spirit"):
		targets = grabs.area_targets()
		if enemy is Zombie000Base and targets.is_empty():
			_wait_for_water_entry(grabs)
			return
	elif enemy is Zombie000Base:
		targets.append(enemy)
	_is_attacking = true
	detect_component.disable_component(ComponentNormBase.E_IsEnableFactor.Attack)
	blink_component.disable_component(ComponentNormBase.E_IsEnableFactor.Attack)
	_grap_in_pool(enemy, targets, grabs)

## [param grabs] 保留原战局资格；等待时只复核原生索敌区内已经重叠的角色。
func _wait_for_water_entry(grabs: AdventureTanglekelpGrabs) -> void:
	if _water_entry_recheck_pending:
		return
	_water_entry_recheck_pending = true
	var origin: PlantCell = plant_cell # 同一次等待复用邻格身份，平台移动仍实时读取空间坐标。
	var cells: Array[PlantCell] = AdventureTanglekelpGrabs.neighborhood(origin) # 到实际出手时才查询全套范围目标。
	while true: # 离场、清空索敌区或开始攻击即停止等待。
		await get_tree().create_timer(WATER_ENTRY_RECHECK_SECONDS, false).timeout
		if not _can_start_grab() or not grabs.battle.is_active():
			break
		if origin != plant_cell:
			origin = plant_cell
			cells = AdventureTanglekelpGrabs.neighborhood(origin)
		var overlapping: Array[Character000Base] = detect_component.get_all_enemy_can_be_attacked() # 沿用原生重叠结果与去重。
		if overlapping.is_empty():
			break
		for enemy: Character000Base in overlapping: # 非水域或已失去资格的重叠不会触发范围扫描。
			if enemy is Zombie000Base and grabs.is_area_target(enemy, cells):
				_water_entry_recheck_pending = false
				start_grap_zombie()
				return
	_water_entry_recheck_pending = false

## 对 [param targets] 播放原生拖拽，[param grabs] 保存可选的海草击杀结算。
## 原索敌为 [param enemy] 中的僵王或构筑物时，保留其穿透伤害和植物下沉。
func _grap_in_pool(enemy: Character000Base, targets: Array[Zombie000Base], grabs: AdventureTanglekelpGrabs) -> void:
	if grabs != null:
		grabs.start(grap_component, targets)
	elif not targets.is_empty():
		grap_component.grab_zombie(targets[0])
	if enemy is Zombie000Base:
		await get_tree().create_timer(PLANT_SPLASH_AT, false).timeout
		if is_death or is_queued_for_deletion() or not is_instance_valid(plant_cell):
			return
		Splash.spawn(plant_cell, global_position + Vector2(0, 10), 1.3)
		await get_tree().create_timer(GrapComponent.HOLD_SECONDS + GrapComponent.SINK_SECONDS - PLANT_SPLASH_AT, false).timeout
	else:
		enemy.be_attacked_bullet(battle_damage(boss_attack_value), BulletRegistry.AttackMode.Penetration, false, false)
		await _sink_after_boss_hit()
	if not is_death and not is_queued_for_deletion():
		character_death()

## 僵王与构筑物的扩展分支沿用植物自己的下沉表现。
func _sink_after_boss_hit() -> void:
	await get_tree().create_timer(0.3, false).timeout
	if is_death or is_queued_for_deletion() or not is_instance_valid(plant_cell):
		return
	Splash.spawn(plant_cell, global_position + Vector2(0, 10))
	var tween: Tween = create_tween() # 只补间水草的退场位置。
	tween.tween_property(self, ^"position:y", 10.0, 0.5).as_relative()
	await tween.finished

