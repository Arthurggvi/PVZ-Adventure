## 统一建造战场中的单体与整组僵王。角色入树前的准备、定位和发布由此完成，登记及计数属于 ZombieManager。
extends RefCounted

## [param boss_type] 已注册的僵王类型；正式战斗、有效根节点及关卡出生点允许时返回 true。
## [param manager] 提供场地、出生位置与战斗状态；卡牌资格不依赖自动出场配置、出怪模式或场上数量。
static func can_summon(manager: ZombieManager, boss_type: CharacterRegistry.ZombieBossType) -> bool:
	if not manager.is_game_running() or not is_instance_valid(manager.zombie_boss_root) \
		or not manager.zombie_boss_root.is_inside_tree() or manager.zombie_boss_root.is_queued_for_deletion() \
		or not manager.game_para.boss_spawn_position.is_finite() \
		or not Global.character_registry.ZombieBossInfo.has(boss_type):
		return false
	# 场景来自注册表，未注册或无法实例化的类型不能消耗卡牌。
	var scene: PackedScene = Global.character_registry.get_zombie_boss_info(
		boss_type, CharacterRegistry.ZombieBossInfoAttribute.BossScenes
	) as PackedScene
	return scene != null and scene.can_instantiate()


## [param manager] 持有登记与计数。[param boss_type] 注册类型；[param spawn_position] 为僵王根节点下的本地位置，INF 使用关卡配置。[br]
## [param count_as_new] 恢复存档时为 false，避免累计生成数重复增加。[br]
## [param restored_hp] 为正数时恢复存活血量，-1 沿用满血。[br]
## [param restored_home_x] 为存档中的本地待机横坐标，INF 表示旧存档未保存该值。
## [param encounter] 为冒险遭遇登场设置；最大生命在入树前应用，登场比例在音乐和血条同步前应用。
## [param on_registered] 只用于连接正式遭遇观察者；成功返回新实例，失败返回 null。
static func create(manager: ZombieManager, boss_type: CharacterRegistry.ZombieBossType, spawn_position: Vector2 = Vector2.INF,
	count_as_new: bool = true, restored_hp: int = -1, restored_home_x: float = INF,
	encounter: BossEncounterDefinition = null, on_registered: Callable = Callable()) -> ZB000Base:
	if not manager.can_summon_boss(boss_type) or (spawn_position != Vector2.INF and not spawn_position.is_finite()):
		return null
	var boss := _prepare_boss_instance(boss_type) # 与整批增援共用角色、生命和初始模式校验。
	if boss == null:
		return null
	if encounter != null and encounter.max_health_multiplier != 1.0:
		var health: HpComponent = boss.get_node("%HpComponent") as HpComponent # 树外使用工厂已校验的本体生命组件。
		# 入树后以遭遇实际生命初始化满血和阶段门槛，与图鉴读取同一换算。
		health.set_spawn_max_health(encounter.resolve_max_health(health.max_hp))
	# 先连接信号并计数，再触发角色 _ready，避免初始化期间发出的通知被遗漏。
	if not manager.register_boss(boss, boss_type, count_as_new):
		boss.free()
		return null
	if on_registered.is_valid():
		on_registered.call(boss)
	# 调用方位置优先，关卡坐标次之，两者均未指定时由各僵王提供默认位置。
	if spawn_position == Vector2.INF and manager.game_para.boss_spawn_position == Vector2.ZERO:
		if count_as_new:
			manager.place_boss_at_default_spawn(boss)
		else:
			boss.place_boss_at_spawn(manager, boss.get_default_boss_spawn_position(manager), restored_home_x)
	else:
		# 明确指定或从存档读取的位置，不参与自动分路。
		var position_override: Vector2 = manager.game_para.boss_spawn_position if spawn_position == Vector2.INF else spawn_position
		boss.place_boss_at_spawn(manager, position_override, restored_home_x)
		if not count_as_new and not is_finite(restored_home_x):
			# 旧存档只有当前位置，回到该行默认右侧待机点。
			var default_home: Vector2 = manager.game_para.boss_spawn_position
			if default_home == Vector2.ZERO:
				default_home = boss.get_default_boss_spawn_position(manager, boss.lane)
			boss.boss_home_x = manager.zombie_boss_root.to_global(default_home).x
	manager.zombie_boss_root.add_child(boss)
	# 入场回调可以同步释放角色。登记时已接入的观察者负责其离场，不再访问失效节点。
	if not is_instance_valid(boss):
		return null
	if boss.is_death or boss.is_queued_for_deletion():
		return boss
	# 子节点已初始化，状态机尚未执行延迟启动；恢复血量不会重放上轮技能中间状态。
	if restored_hp > 0:
		boss.restore_boss_hp(restored_hp)
	if is_instance_valid(boss) and not boss.is_death and not boss.is_queued_for_deletion() and encounter != null:
		boss.configure_adventure_encounter(encounter.initial_health_ratio,
			encounter.retreat_after_phase_two, encounter.skill_summon_tier)
	# 登记发生在入树前，音乐通知必须等入树完成，存活快照才能包含本次实例。
	if is_instance_valid(boss):
		manager.publish_boss_spawns([boss])
	return boss if is_instance_valid(boss) else null


## [param boss_type] 从公共注册表取材；[param positions] 为同类型增援在僵王容器中的有限坐标。[param prepare] 在树外按顺序接收实例和序号，返回能否提交。
## [param manager] 提供战场登记和根节点。[param commit_origin] 在整批完成入树、向遭遇及血条公开之前提交原体变化。失败返回空数组，不占用计数或触发离场。
static func create_reinforcements(manager: ZombieManager, boss_type: CharacterRegistry.ZombieBossType, positions: Array[Vector2],
		prepare: Callable, commit_origin: Callable) -> Array[ZB000Base]:
	var members: Array[ZB000Base] = [] # 全部准备成功以前，实例只由此处持有。
	if positions.is_empty() or not manager.can_summon_boss(boss_type) or not prepare.is_valid() or not commit_origin.is_valid():
		return members
	for index: int in positions.size(): # 用序号把独立出生点与本次初始状态配对。
		if not positions[index].is_finite():
			break
		var member := _prepare_boss_instance(boss_type, prepare.bind(index)) # 失败的实例在工厂内部释放。
		if member == null:
			break
		members.append(member)
	if members.size() == positions.size():
		for index: int in members.size(): # 出生脚点在观察者取得整组之前就位。
			members[index].place_boss_at_spawn(manager, positions[index])
	if members.size() != positions.size() or not manager.register_boss_group(members, boss_type):
		for member: ZB000Base in members: # 预检失败尚未入树或计数。
			member.free()
		return []
	for member: ZB000Base in members: # 正式遭遇已取得整组，准备刷新原体和各自的真实生命。
		manager.zombie_boss_root.add_child(member)
	if commit_origin.is_valid():
		commit_origin.call()
	manager.publish_boss_spawns(members)
	return members


## 准备 [param boss_type] 的树外实例；可选 [param prepare] 注入初始状态并返回是否接纳。失败仅回收临时实例。
static func _prepare_boss_instance(boss_type: CharacterRegistry.ZombieBossType, prepare: Callable = Callable()) -> ZB000Base:
	# 资格检查已确认该注册场景可以实例化。
	var scene: PackedScene = Global.character_registry.get_zombie_boss_info(
		boss_type, CharacterRegistry.ZombieBossInfoAttribute.BossScenes
	) as PackedScene
	# 根节点先保持 Node，以便配置错误时释放实际创建的节点。
	var instance: Node = scene.instantiate()
	# 本次新角色，必须符合僵王基础接口。
	var boss: ZB000Base = instance as ZB000Base
	if boss == null:
		push_error("ZombieManager：僵王场景根节点必须继承 ZB000Base。")
		if is_instance_valid(instance):
			instance.free()
		return null
	# 血量子节点先于角色 _ready 初始化；提前拒绝零血量，避免漏接初始化死亡。
	var boss_hp: HpComponent = boss.get_node_or_null("%HpComponent") as HpComponent
	if boss_hp != null and prepare.is_valid():
		var accepted: bool = prepare.call(boss) # 只有明确接受且仍有效的实例允许进入登记。
		if not is_instance_valid(boss):
			return null
		if not accepted or boss.is_queued_for_deletion():
			boss.free()
			return null
	if not is_instance_valid(boss_hp) or boss_hp.max_hp <= 0 or boss.is_death:
		push_error("ZombieManager：僵王必须具有正数初始血量，且不能预设为死亡。")
		boss.free()
		return null
	boss.character_init_type = Character000Base.E_CharacterInitType.IsNorm
	return boss
