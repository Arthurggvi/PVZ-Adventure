extends ComponentNormBase
## 攻击射线检测组件,根据owner自动选择敌人层
class_name DetectComponent

## 每帧判断是否检测当前敌人
## 敌人进入\离开\状态变化时检测
## 敌人进入时连接状态变化函数，离开时不断开
## **植物和僵尸通用**
#region 检测层以及对应的值
## 层类型
enum E_LayType{
	PlantEnemy,		## 植物的敌人
	ZombieEnemy,	## 僵尸的敌人
	Item,			## 道具
}
## 可以检测的道具
enum E_ItemType{
	Brain = 1,	## 脑子（我是僵尸模式）
	Pot = 2,	## 罐子
	Other = 4,	## 占位
}

## 层类型对应的值（检测）
const C_LayTypeValueDetection:Dictionary[E_LayType, int]={
	E_LayType.PlantEnemy:4,		## 僵尸
	E_LayType.ZombieEnemy:2+32,	## 植物+魅惑僵尸
	E_LayType.Item:2048,		## 道具
}
## 攻击中的僵尸状态
const C_AttackZombieDetection:= 16
## 层类型对应的值（真实）
const C_LayTypeValueReal:Dictionary[E_LayType, int]={
	E_LayType.PlantEnemy:512,		## 僵尸
	E_LayType.ZombieEnemy:256+1024,	## 植物+魅惑僵尸
	E_LayType.Item:4096,			## 道具
}
#endregion

## 是否使用行属性进行攻击判断
@export var is_lane:=true
## 检测组件是否为检测层(否时为检测真实层,杨桃)
@export var is_dectection := true
## 是否检测攻击中的僵尸
@export var is_detect_attack:=false
## 只对活体植物触发的接触攻击可跳过独立的友方屏障。
@export var detect_friendly_barriers := true
## 只有物理接触型碾压器会检查藏匿植物，主动攻击保持默认筛选。
var detects_hidden_plant_contacts: bool = false
@export_group("可检测道具")
## 是否检测脑子
@export_flags("1 脑子", "2 罐子", "4 占位") var is_detect_items:int = 0
## 检测到的道具
var brain:BrainOnZombieMode
## 罐子
var pot:ScaryPot

## 当前检测层
var curr_collision_lay:int = 0
## 更新当前检测层，同时改所有的检测节点的检测层
## curr_character[int]: 当前角色，用于判断敌人类型，1:植物的敌人，2:僵尸的敌人, 3:两者都有
func update_curr_collision_lay(curr_character:int):
	## 如果检测层面
	if is_dectection:
		_set_curr_collision_lay_value(curr_character, C_LayTypeValueDetection)

		if is_detect_attack:
			curr_collision_lay |= C_AttackZombieDetection
	else:
		_set_curr_collision_lay_value(curr_character, C_LayTypeValueReal)

	## 更新所有检测区域的敌人mask层
	for node in get_children():
		if node is Area2D:
			var area_2d = node as Area2D
			area_2d.collision_mask = curr_collision_lay
## 设置当前检测层
## curr_character[int]: 当前角色，用于判断敌人类型，1:植物的敌人，2:僵尸的敌人, 3:两者都有
## lay_type_value[Dictionary]: 检测层面\真实层面对应的检测层数值
func _set_curr_collision_lay_value(curr_character:int, lay_type_value:Dictionary[E_LayType, int]):
	curr_collision_lay = 0
	if curr_character & 1:
		curr_collision_lay |= lay_type_value[E_LayType.PlantEnemy]
	if curr_character & 2:
		curr_collision_lay |= lay_type_value[E_LayType.ZombieEnemy]
	## 检测道具
	if is_detect_items != 0:
		curr_collision_lay |= lay_type_value[E_LayType.Item]

## 是否攻击梯子下的植物,僵尸初始化时根据is_ignore_ladder更新该值，默认攻击，僵尸一般不攻击，只有巨人和冰车攻击
var is_attack_ladder_plant:=true

## 检测到的敌人
## (不能攻击是因为敌人状态不在攻击状态中，连接状态变化信号)
## 检测到的可以被攻击的一个敌人,给特殊植物\僵尸\抛物线子弹使用
var enemy_can_be_attacked :Character000Base = null
## 是否需要判断检测敌人
var need_judge := false:
	set(value):
		need_judge = value
		# 仅重叠或目标状态产生变化时唤醒更新，保留在渲染帧末前的合并判断。
		set_process(value and is_enabling)

## 检测区域列表
var all_ray_area:Array[Area2D]
## 检测区域的方向,部分植物发射子弹使用
var ray_area_direction:Array[Vector2]
@export_group("可以攻击的敌人状态")
## 可以攻击的敌人状态
@export_flags("1 正常", "2 悬浮", "4 地刺", "8 低矮") var can_attack_plant_status:int = 9
@export_flags("1 正常", "2 跳跃", "4 水下", "8 空中", "16 地下") var can_attack_zombie_status:int = 1

## 外部需要的组件（攻击行为组件）连接该信号
## 检测到可攻击敌人，可以攻击信号
signal signal_can_attack
## 无可攻击敌人，取消攻击信号
signal signal_not_can_attack

func _ready() -> void:
	set_process(need_judge and is_enabling)
	if owner is Plant000Base:
		update_curr_collision_lay(1)
		owner.combat_lane_changed.connect(_on_combat_lane_changed)
	elif owner is Zombie000Base:
		update_curr_collision_lay(2)
	elif owner is MainGameManager:
		update_curr_collision_lay(1)
	else:
		printerr("组件owner不是植物或者僵尸基类角色")

	## 连接所有子节点（area2d）的信号[三线、杨桃等有多个射线area2d]
	for i:int in range(get_child_count()):
		var area_2d:Area2D = get_child(i)
		area_2d.area_entered.connect(_on_area_2d_area_entered)
		area_2d.area_exited.connect(_on_area_2d_area_exited)
		all_ray_area.append(area_2d)
		ray_area_direction.append(Vector2(cos(area_2d.rotation), sin(area_2d.rotation)))

	## 如果是角色类型(世界有一个全局检测组件,用于追踪型子弹检查敌人)
	if owner is Character000Base and owner.lane == -1 and owner.character_init_type == Character000Base.E_CharacterInitType.IsNorm:
		printerr(owner.name + "lane == -1且为正常出战初始化类型")

func _process(_delta):
	if need_judge and is_enabling:
		need_judge = false
		judge_is_have_enemy()

## 启用组件
func enable_component(is_enable_factor:E_IsEnableFactor):
	super(is_enable_factor)
	if is_enabling:
		need_judge = true

## 禁用组件
func disable_component(is_enable_factor:E_IsEnableFactor):
	super(is_enable_factor)
	enemy_can_be_attacked = null
	signal_not_can_attack.emit()
	need_judge = false

#region 敌人进入、离开或状态更新（植物：梯子状态、僵尸：状态）
## 敌人进入当前区域，若为同一行，当前帧进行判断是否可以攻击
func _on_area_2d_area_entered(area: Area2D) -> void:
	var enemy = area.owner
	# 道具仍由后续查询处理，不读取非角色节点的行属性。
	if not enemy is Character000Base:
		need_judge = true
		return
	if is_lane and not (enemy is ZB000Base or enemy is FriendlyBattleBarrier) and owner.lane != enemy.lane \
			and not (enemy is Zombie000Base and (enemy as Zombie000Base).covers_attack_lane(owner.lane)):
		var game: MainGameManager = Global.main_game # 静态棋盘仍在物理入区时过滤异行角色。
		if not is_instance_valid(game) or game.board == null or game.board.definition == null \
				or not game.board.definition.project_surface_combat_lanes:
			return
	# 浮台可能在双方仍重叠时跨行。订阅后仍由选敌查询复核实际同行资格。
	if is_lane and enemy is Plant000Base and not enemy.combat_lane_changed.is_connected(_on_combat_lane_changed):
		enemy.combat_lane_changed.connect(_on_combat_lane_changed)
	if enemy is ZB000Base:
		if not enemy.signal_status_update.is_connected(_on_enemy_boss_status_update):
			enemy.signal_status_update.connect(_on_enemy_boss_status_update)
	elif enemy is Plant000Base:
		if not enemy.signal_ladder_update.is_connected(_on_enemy_plant_ladder_update.bind(enemy)):
			enemy.signal_ladder_update.connect(_on_enemy_plant_ladder_update.bind(enemy))
		if owner is Zombie000Base:
			_watch_plant_freeze(enemy)
	elif enemy is Zombie000Base:
		if not enemy.signal_status_update.is_connected(_on_enemy_zombie_status_update.bind(enemy)):
			enemy.signal_status_update.connect(_on_enemy_zombie_status_update.bind(enemy))
		if not enemy.signal_lane_update.is_connected(_on_enemy_zombie_lane_update.bind(enemy)):
			enemy.signal_lane_update.connect(_on_enemy_zombie_lane_update.bind(enemy))
	# 使用具名回调去重；多个区域重叠同一角色时也只订阅一次。
	if not enemy.signal_character_death.is_connected(_on_enemy_target_removed):
		enemy.signal_character_death.connect(_on_enemy_target_removed)
	if not enemy.tree_exiting.is_connected(_on_enemy_target_removed):
		enemy.tree_exiting.connect(_on_enemy_target_removed)
	need_judge = true


## 平台换行可能先于下次物理进出通知，重新检查已有重叠。
func _on_combat_lane_changed() -> void:
	need_judge = true

## 状态变化只标记重查；受击框实际启停产生的进入/退出事件仍会再次刷新重叠结果。
func _on_enemy_boss_status_update() -> void:
	need_judge = true


## 死亡或移除后重新选取目标，不能把旧的敌人引用继续用于攻击。
func _on_enemy_target_removed() -> void:
	need_judge = true

## 敌人离开当前射线检测区域
@warning_ignore("unused_parameter")
func _on_area_2d_area_exited(area: Area2D) -> void:
	need_judge = true

## 植物敌人梯子状态变化
@warning_ignore("unused_parameter")
func _on_enemy_plant_ladder_update(plant:Plant000Base):
	need_judge = true

## 订阅 [param plant] 的冻结变化；同格保护层即使由另一株的重叠选中，也要能刷新目标。
func _watch_plant_freeze(plant: Plant000Base) -> void:
	if not plant.signal_cold_frozen_changed.is_connected(_on_enemy_plant_frozen_changed):
		plant.signal_cold_frozen_changed.connect(_on_enemy_plant_frozen_changed)

## 立即丢弃冻结目标，防止下一次伤害或咬合帧使用旧引用；重叠结果仍由合并查询更新。
func _on_enemy_plant_frozen_changed() -> void:
	if is_instance_valid(enemy_can_be_attacked) and enemy_can_be_attacked is Plant000Base \
			and enemy_can_be_attacked.is_cold_frozen():
		enemy_can_be_attacked = null
	need_judge = true

## 僵尸敌人状态变化时函数，与状态变化信号连接
@warning_ignore("unused_parameter")
func _on_enemy_zombie_status_update(zombie:Zombie000Base):
	need_judge = true

## 僵尸敌人行变化时函数，与行变化信号连接
@warning_ignore("unused_parameter")
func _on_enemy_zombie_lane_update(zombie:Zombie000Base):
	need_judge = true
#endregion

#region 检测是否有敌人\道具
## 按射线和各区域的原遍历顺序收集重叠结果，返回是否有可攻击的角色或道具。
func judge_is_have_enemy() -> bool:
	var areas: Array[Area2D] = [] # 同一组候选供屏障优先筛选和普通目标遍历使用。
	for ray: Area2D in all_ray_area: # 射线顺序决定同优先级目标的遍历次序。
		areas.append_array(ray.get_overlapping_areas())
	return judge_enemy_in_areas(areas)

## 从 [param areas] 的重叠结果中选取可攻击的角色或道具，更新目标并发射检测信号。
## 同时适用于监听区域及即时物理查询；返回是否选中目标。
func judge_enemy_in_areas(areas: Array[Area2D]) -> bool:
	if detect_friendly_barriers and owner is Zombie000Base and get_tree().has_group(FriendlyBattleBarrier.GROUP):
		for area: Area2D in areas: # 屏障贴到植物时，重叠范围内的地面攻击仍优先交给屏障。
			if area.owner is FriendlyBattleBarrier and _on_detect_character(area.owner):
				signal_can_attack.emit()
				return true
	for area: Area2D in areas: # 其余重叠按原顺序检查角色及道具资格。
		if area.owner is Character000Base:
			if _on_detect_character(area.owner):
				signal_can_attack.emit()
				return true
		elif area.owner is MainGameItemBase:
			if _on_detect_main_game_item(area.owner):
				signal_can_attack.emit()
				return true
	enemy_can_be_attacked = null
	signal_not_can_attack.emit()
	return false

## 当检测到道具
func _on_detect_main_game_item(curr_main_game_item:MainGameItemBase)->bool:
	## 可以检测罐子 并且 检测到罐子
	if is_detect_items & E_ItemType.Pot and curr_main_game_item is ScaryPot:
		print("检测到罐子")
		pot = curr_main_game_item
		return true
	## 可以检测脑子 并且 检测到脑子
	elif is_detect_items & E_ItemType.Brain and curr_main_game_item is BrainOnZombieMode:
		print("检测到脑子")
		brain = curr_main_game_item
		return true
	else:
		#print("未检测到道具")
		return false

## 当检测到角色
func _on_detect_character(enemy:Character000Base) -> bool:
	## 如果角色可以被攻击，更新当前可以被攻击的角色
	if _judge_enemy_is_can_be_attack(enemy):
		if enemy is Plant000Base:
			enemy_can_be_attacked = get_first_be_hit_plant_in_cell(enemy, owner is Zombie000Base)
		elif enemy is Zombie000Base or enemy is ZB000Base or enemy is EnemyStructureBase or enemy is FriendlyBattleBarrier:
			enemy_can_be_attacked = enemy
		if not is_instance_valid(enemy_can_be_attacked):
			return false
		if not enemy_can_be_attacked.signal_character_death.is_connected(_on_enemy_target_removed):
			enemy_can_be_attacked.signal_character_death.connect(_on_enemy_target_removed)
		return true
	else:
		return false

## [param plant] 是实际碰撞植物；壳与普通层仍优先，伴生在承托层之前受击。
## [param skip_frozen] 用于僵尸接触索敌，雪球瞄准仍能查询具有拦截资格的冰封层。
func get_first_be_hit_plant_in_cell(plant: Plant000Base, skip_frozen: bool = false) -> Plant000Base:
	if not is_instance_valid(plant) or not is_instance_valid(plant.plant_cell):
		return null
	var cell: PlantCell = plant.plant_cell # 读取当前格子，不缓存已经移除的目标。
	for slot: CharacterRegistry.PlacePlantInCell in [CharacterRegistry.PlacePlantInCell.Shell,
			CharacterRegistry.PlacePlantInCell.Norm, CharacterRegistry.PlacePlantInCell.Imitater]: # 保留既有前排优先级。
		var candidate: Variant = cell.plant_in_cell.get(slot) # 模仿者槽可能不存在，必须使用安全查询。
		if _can_hit_plant_layer(candidate, skip_frozen):
			return candidate as Plant000Base
	var accept_companion: Callable = _can_hit_companion.bind(skip_frozen) # 伴生沿用正常占位的主动攻击资格。
	var companion: Plant000Base = cell.first_companion_plant(accept_companion) # 不占位植物仍可被普通僵尸啃食。
	if companion != null:
		return companion
	var support: Variant = cell.plant_in_cell.get(CharacterRegistry.PlacePlantInCell.Down) # 前排为空才攻击承托。
	if _can_hit_plant_layer(support, skip_frozen):
		return support as Plant000Base
	var floating: Variant = cell.plant_in_cell.get(CharacterRegistry.PlacePlantInCell.Float) # 保留悬浮状态资格。
	if (can_attack_plant_status & 2) and _can_hit_plant_layer(floating, skip_frozen):
		return floating as Plant000Base
	return null

## [param candidate] 是当前种植层的引用，可不存在；[param skip_frozen] 控制接触攻击的冻结过滤。
func _can_hit_plant_layer(candidate: Variant, skip_frozen: bool) -> bool:
	return is_instance_valid(candidate) and not candidate.is_death and not candidate.is_queued_for_deletion() \
		and _can_focus_plant(candidate) and (not skip_frozen or _is_unfrozen_plant(candidate))

## 为 [param plant] 区分主动索敌与沿路接触；非敌方查询可照常读取植物。
func _can_focus_plant(plant: Plant000Base) -> bool:
	return not plant.battle_hidden_from_zombies or detects_hidden_plant_contacts \
		or not (owner is Zombie000Base or owner is ZB000Base)

## [param plant] 为正式伴生候选，[param skip_frozen] 为现有的啃食冻结规则。
func _can_hit_companion(plant: Plant000Base, skip_frozen: bool) -> bool:
	return _can_focus_plant(plant) and (not skip_frozen or _is_unfrozen_plant(plant))

## 订阅已经进入索敌范围的 [param plant]，返回该层是否未冻结。
func _is_unfrozen_plant(plant: Plant000Base) -> bool:
	_watch_plant_freeze(plant)
	return not plant.is_cold_frozen()

## 判断敌人状态是否可以被攻击
func _judge_enemy_is_can_be_attack(enemy:Character000Base)->bool:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy.is_death:
		return false
	if enemy is FriendlyBattleBarrier:
		return detect_friendly_barriers and owner is Zombie000Base and enemy.can_intercept(owner) \
			and (can_attack_plant_status & Plant000Base.E_BeAttackStatusPlant.IsNorm) != 0
	# 魅惑僵尸跳过僵王。其余攻击者由受击组件读取僵王的受击窗口。
	if enemy is ZB000Base:
		return not (owner is Zombie000Base and owner.is_hypno) \
			and enemy.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
			and is_instance_valid(enemy.hurt_box_component) and enemy.hurt_box_component.is_enabling \
			and (can_attack_zombie_status & Zombie000Base.E_BeAttackStatusZombie.IsNorm) != 0
	## 先判断行属性
	if is_lane and owner.lane != enemy.lane \
			and not (enemy is Zombie000Base and (enemy as Zombie000Base).covers_attack_lane(owner.lane)):
		return false
	if enemy is EnemyStructureBase:
		return enemy.hurt_box_component.is_enabling \
			and (can_attack_zombie_status & Zombie000Base.E_BeAttackStatusZombie.IsNorm) != 0
	## 如果敌人为植物
	if enemy is Plant000Base:
		return _can_focus_plant(enemy) and (enemy.curr_be_attack_status & can_attack_plant_status) != 0 \
			and (not owner is Zombie000Base or not enemy.is_cold_frozen())

	elif enemy is Zombie000Base:
		if enemy.curr_be_attack_status & can_attack_zombie_status:
			return true
		else:
			return false

	## 其余东西
	else:
		#print("检测到非角色类敌人")
		return false

#endregion

#region 检测组件提供的通用方法
## 更新可攻击敌人为第一个敌人(最前面的敌人),投手类使用
func update_first_enemy()->Character000Base:
	enemy_can_be_attacked = null
	for ray_area in all_ray_area:
		var all_enemy_area = ray_area.get_overlapping_areas()
		for enemy_area in all_enemy_area:
			var enemy := enemy_area.owner as Character000Base
			## 如果敌人可以被攻击
			if _judge_enemy_is_can_be_attack(enemy):
				if is_instance_valid(enemy_can_be_attacked):
					# 博士根节点可远离受击框，排序统一依据实际受击组件的位置。
					if enemy_can_be_attacked.hurt_box_component.global_position.x > enemy.hurt_box_component.global_position.x:
						enemy_can_be_attacked = enemy
				else:
					enemy_can_be_attacked = enemy
	#print(enemy_can_be_attacked.global_position.x, enemy_can_be_attacked.name)
	return enemy_can_be_attacked


## 按受击框遍历顺序返回可攻击的角色。同一角色只收录第一次通过资格检查的结果。
func get_all_enemy_can_be_attacked()->Array[Character000Base]:
	var all_enemy_can_be_attacked: Array[Character000Base] = [] # 按原遍历顺序收录。
	var seen: Dictionary[int, bool] = {} # 不必对每个受击框重复线性搜索输出数组。
	for ray_area: Area2D in all_ray_area: # 每条射线使用自己的当前重叠集合。
		for enemy_area: Area2D in ray_area.get_overlapping_areas(): # 同一角色可能由多个受击框命中。
			var enemy := enemy_area.owner as Character000Base # 道具没有角色受击资格。
			# 保持各检测组件逐受击框的资格判断及其状态更新，例如倭瓜的锁定。
			if enemy == null or not _judge_enemy_is_can_be_attack(enemy):
				continue
			var id: int = enemy.get_instance_id() # 用同一角色实例的身份去重。
			if not seen.has(id):
				seen[id] = true
				all_enemy_can_be_attacked.append(enemy)
	return all_enemy_can_be_attacked

#endregion

#region 被魅惑
## 僵尸被魅惑
func owner_be_hypno():
	update_curr_collision_lay(1)
	disable_component(ComponentNormBase.E_IsEnableFactor.Hypno)
	enable_component(ComponentNormBase.E_IsEnableFactor.Hypno)
#endregion

#region 特殊使用：仙人掌、全局攻击
## 判断是否有空中僵尸敌人
func judge_zombie_in_sky() -> bool:
	for ray_area in all_ray_area:
		var all_enemy_area = ray_area.get_overlapping_areas()
		for enemy_area in all_enemy_area:
			if enemy_area.owner is Character000Base:
				var enemy:Character000Base = enemy_area.owner
				## 复用存活及行状态判断，避免选中已经死亡的空中僵尸。
				if not _judge_enemy_is_can_be_attack(enemy):
					continue
				## 检测到僵尸 and 可以攻击状态 and 在空中
				if enemy is Zombie000Base \
				and enemy.curr_be_attack_status & can_attack_zombie_status \
				and enemy.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsSky:
					enemy_can_be_attacked = enemy
					return true
	return false



## 更新敌人 enemy_can_be_attacked,追踪型子弹
##TODO: 全局子弹判定敌人(植物)
"""
追踪子弹首次检测敌人直接锁定,直到敌人死亡,在选择下一个敌人(当前检测组件保存敌人)，若敌人死亡，重新选择
第一次索敌时有空中敌人先攻击空中敌人
选择敌人时按照靠近房子的顺序选择
发射子弹的植物,若前一格有敌人,优先索敌前一格敌人,不使用全局索敌
"""
func update_enemy_track_bullet() -> Character000Base:
	## 所有的可以攻击的敌人
	var all_enemy_can_be_attacked:Array[Character000Base] = get_all_enemy_can_be_attacked()
	# 重新获取目标时清理旧引用，避免已死亡或禁用受击的旧目标参与排序。
	enemy_can_be_attacked = null
	## 是否有空中敌人
	var is_have_sky_enemy:= false
	for enemy:Character000Base in all_enemy_can_be_attacked:
		if not (enemy is Zombie000Base or enemy is ZB000Base or enemy is EnemyStructureBase):
			continue
		# 仅普通僵尸具有空中状态字段；僵王按地面目标参与排序。
		var is_sky: bool = enemy is Zombie000Base and enemy.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsSky
		if not is_instance_valid(enemy_can_be_attacked) or (is_sky and not is_have_sky_enemy):
			enemy_can_be_attacked = enemy
			is_have_sky_enemy = is_sky
		elif is_sky == is_have_sky_enemy \
			and enemy.hurt_box_component.global_position.x < enemy_can_be_attacked.hurt_box_component.global_position.x:
			enemy_can_be_attacked = enemy

	return enemy_can_be_attacked

#endregion
