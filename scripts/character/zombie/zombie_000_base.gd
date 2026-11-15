extends Character000Base
class_name Zombie000Base


@onready var attack_component: AttackComponentBase = %AttackComponent
@onready var hp_stage_change_component: HpStageChangeComponent = %HpStageChangeComponent
@onready var charred_component: CharredComponent = %CharredComponent
@onready var move_component: MoveComponent = %MoveComponent
@onready var swim_box_component: SwimBoxComponent = %SwimBoxComponent
@onready var drop_item_component: DropItemComponent = %DropItemComponent

#region 僵尸类基础属性
@export var zombie_type:CharacterRegistry.ZombieType
## 僵尸基础属性参数，_ready初始化
@export_group("僵尸基础属性")
## 是否忽略梯子,即可以攻击梯子下的植物
@export var is_ignore_ladder:=false
## 是否为小僵尸大麻烦的小僵尸(速度翻倍,大小,血量减半)
var is_mini_zombie:= false
## 是否为罐子创建的僵尸
var is_pot_zombie:=false
## 是否正在从地下出现
var is_body_up_from_ground := false

@export_subgroup("僵尸铁器")
## 铁器种类
enum IronType{
	Null,		## 没有铁器
	IronArmor1,	## 一类铁器防具
	IronArmor2,	## 二类铁器防具
	IronItem,	## 铁器道具
}

## 僵尸铁器类型
@export var iron_type:IronType = IronType.Null

## 受弹命中产生的水平击退，方向固定背离正常植物阵地。
## [param distance] 击退像素，非正值及死亡角色无效；重置行走基准防止动画位移抵消。
func apply_projectile_knockback(distance: float) -> void:
	if distance > 0.0 and is_instance_valid(move_component):
		move_component.apply_forced_displacement(Vector2(distance, 0.0))
## 僵尸铁器节点
@export var iron_node:IronNode
@export_subgroup("僵尸初始化状态")
## 僵尸初始化状态（从1[is_norm] 开始，被攻击时是否能被攻击到的属性）
@export var init_be_attack_status :E_BeAttackStatusZombie = E_BeAttackStatusZombie.IsNorm
## 僵尸出生波次
var curr_wave:=-1
## 本局冒险自然波次分配的独立等阶标识；原版/技能僵尸为空。
var adventure_tier_id: StringName = &""
## 沉默按来源独立计数，任一来源存在时等阶技能暂停。
var _tier_suppressors: Dictionary[int, bool] = {}
## 死亡过程开始后冻结等阶资格，清理负面状态不能重新激活亡语。
var _tier_death_state_set := false
## 死亡瞬间的等阶技能资格，和基础生命/攻击成长无关。
var _tier_active_at_death := true
## 原生行为期望的根朝向；0 表示尚未捕获场景的初始朝向。
var _native_direction_x_root: int = 0
## 持续能力据此撤销或恢复自己的输出，禁止重建初始化奖励。
signal signal_tier_skills_changed(active: bool)

## 设置 [param source_id] 的沉默 [param suppressed]，死亡期间只清理登记而不改变冻结资格。
func set_tier_suppressed(source_id: int, suppressed: bool) -> void:
	var before: bool = are_tier_skills_active() # 只在总资格改变时广播。
	if suppressed:
		_tier_suppressors[source_id] = true
	else:
		_tier_suppressors.erase(source_id)
	if not _tier_death_state_set and before != are_tier_skills_active():
		signal_tier_skills_changed.emit(are_tier_skills_active())

## 返回等阶能力资格；基础星级生命与伤害倍率始终保留。
func are_tier_skills_active() -> bool:
	return _tier_active_at_death if _tier_death_state_set else _tier_suppressors.is_empty()

## 在任何死亡信号前记录沉默，避免负面节点的死亡清理顺序改变亡语结果。
func _capture_tier_death_state() -> void:
	if not _tier_death_state_set:
		_tier_active_at_death = _tier_suppressors.is_empty()
		_tier_death_state_set = true

## 返回是否仍为载具整体；散架后的单个雪橇僵尸属于普通僵尸。
func is_vehicle() -> bool:
	return zombie_type in [CharacterRegistry.ZombieType.Z013Zamboni,
		CharacterRegistry.ZombieType.Z014Bobsled, CharacterRegistry.ZombieType.Z023Catapult]

## [param direction_x] 是原生行为期望的朝向，恐惧只在最终方向上额外取反。
func update_direction_x_root(direction_x: int) -> void:
	_native_direction_x_root = direction_x
	refresh_flee_direction()

## 重新合成原生朝向与恐惧，不恢复旧快照；恐惧期间魅惑、矿工转身仍可改变原生朝向。
func refresh_flee_direction() -> void:
	if _native_direction_x_root == 0:
		_native_direction_x_root = direction_x_root
	var reversed: bool = is_instance_valid(move_component) and move_component.is_fleeing() # 恐惧不写 is_hypno。
	super.update_direction_x_root(_native_direction_x_root * (-1 if reversed else 1))
	if is_instance_valid(move_component):
		move_component.update_previous_ground_global_x()

## 向右击退越过清场边界后，允许仍在向战场移动的僵尸走回来。
var nonlethal_displacement_exile := false
## Original combat spawn modifier; used to derive explicit child-spawn policy.
var combat_spawn_modifier: ZombieSpawnModifier = null

func inherited_child_modifier() -> ZombieSpawnModifier:
	return combat_spawn_modifier.for_child() if combat_spawn_modifier != null else null
## 是否参与自然出怪的提前刷新数量统计；博士召唤及其衍生僵尸为 false，全场计数不受影响。
var participates_natural_refresh: bool = true
## 战场内换行会短暂离树；管理器在这次重挂期间保留原有登记。
var is_changing_lane := false
## 僵尸当前状态
var curr_be_attack_status:E_BeAttackStatusZombie=E_BeAttackStatusZombie.IsNorm:
	set(value):
		curr_be_attack_status = value
		signal_status_update.emit()

## 当前僵尸所在行，陆地、水池
var curr_zombie_row_type:CharacterRegistry.ZombieRowType=CharacterRegistry.ZombieRowType.Land
## 水路两栖僵尸当前行为水路时body变化
@export var body_change_on_pool:ResourceBodyChange

## 是否可以触发倭瓜位置判定，默认都为否，可以跳跃的僵尸跳跃组件跳跃后修改为否
@export var is_trigger_squash_pos_judge := false
## 是否可以高建国强行停止跳跃判定，默认都为否，可以跳跃的僵尸跳跃组件跳跃后修改为否
@export var is_trigger_tall_nut_stop_jump := false

## 状态更新信号
signal signal_status_update
## 行更新信号
signal signal_lane_update
#func _update_lane(new_lane):
	#lane = new_lane
	#signal_lane_update.emit()

## 僵尸掉血信号（只有僵尸使用）,参数为损失的血量值
signal signal_zombie_hp_loss(all_loss_hp:int, wave:int)

#endregion

#region 角色枚举
## 检测攻击时，根据状态判断是否可以攻击
enum E_BeAttackStatusZombie{
	IsNorm = 1,		## 正常
	IsJump = 2,		## 跳跃
	IsDownPool = 4,		## 水下
	IsSky = 8,			## 空中
	IsDownGround = 16,	## 地下
	IsJumpInPool = 32,	## 跳入泳池,该状态无法被高建国拦截
}

#endregion

#region 僵尸动画状态参数
@export_group("动画状态")
## 默认为移动状态,is_walk由多种状态控制
@export var is_walk := true
@export var is_attack := false:
	set(value):
		is_attack = value
		_judge_is_walk()
@export var is_swimming := false
##是否为珊瑚僵尸
var is_seaweed:=false
## 父类通用
#var is_death := false

## 被炸死
var is_bomb_death := false:
	set(value):
		is_bomb_death = value
		_judge_is_walk()

## is_walk由is_attack 和 is_bomb_death控制
func _judge_is_walk():
	is_walk = not is_attack and not is_bomb_death

#endregion

@export_group("入场音效")
@export var sfx_enter_name:StringName
## 入场音效
var sfx_enter:AudioStreamPlayer
var is_sfxing:=false
## 停止入场音效(死亡\失去小丑盒子)
func _stop_sfx_enter():
	if is_sfxing:
		sfx_enter.stop()

@export_group("其他")
@export_subgroup("黄油")
## 头的可能的节点路径,黄油糊脸使用,若路径都不对,新增一个对应的路径
var head1_path_candidate:Array[NodePath] = [
	"Body/BodyCorrect/Anim_head/Anim_head1",
	"Body/BodyCorrect/Anim_head1",
	"Body/BodyCorrect/Zombie_head",
	"Body/BodyCorrect/Head/Anim_head1",
	"Body/BodyCorrect/Zombie_catapult_driver_head",
]
## 头的节点
var head_node:Node2D
## 黄油节点,
var butter_splat:Node2D

## 僵尸初始化属性
enum E_ZInitAttr{
	CharacterInitType,	## 角色初始化类型（正常、展示）
	Lane,				## 僵尸行
	CurrZombieRowType,	## 僵尸所在行属性（水、陆地）
	CurrWave,			## 僵尸波次
	IsMiniZombie,		## 是否为小僵尸大麻烦的小僵尸
	IsPotZombie,		## 是否为罐子生成的僵尸，小丑瞬爆
	IsZombieMode,		## 是否为我是僵尸模式的僵尸，气球落地,撑杆食脑
	## 是否参与自然出怪提前刷新，子僵尸继承来源；默认 true 保留原有生成方式的行为。
	ParticipatesNaturalRefresh,
}

## 修改初始化状态，在添加到场景树之前调用
func init_zombie(zombie_init_para:Dictionary):
	self.character_init_type = zombie_init_para.get(E_ZInitAttr.CharacterInitType, E_CharacterInitType.IsNorm)
	self.is_mini_zombie = zombie_init_para.get(E_ZInitAttr.IsMiniZombie, false)
	# 入树前注入来源，供 ready 中的衍生生成和主场景登记使用。
	self.participates_natural_refresh = zombie_init_para.get(E_ZInitAttr.ParticipatesNaturalRefresh, true)
	match self.character_init_type:
		E_CharacterInitType.IsNorm:
			self.is_pot_zombie = zombie_init_para.get(E_ZInitAttr.IsPotZombie, false)
			self.is_zombie_mode = zombie_init_para.get(E_ZInitAttr.IsZombieMode, false)
			self.lane = zombie_init_para.get(E_ZInitAttr.Lane, -1)
			if zombie_init_para.has(E_ZInitAttr.CurrZombieRowType):
				self.curr_zombie_row_type = zombie_init_para[E_ZInitAttr.CurrZombieRowType]
			else:
				self.curr_zombie_row_type = Global.main_game.zombie_manager.all_zombie_rows[lane].zombie_row_type
			self.curr_wave = zombie_init_para.get(E_ZInitAttr.CurrWave, -1)


func _ready() -> void:
	if is_mini_zombie:
		update_mini_zombie()
	super()
	if character_init_type == E_CharacterInitType.IsNorm:
		Global.record_almanac_encounter("zombie", int(zombie_type))
	##INFO: 检测是否有头节点
	var is_have_head:=false
	for head1_path:NodePath in head1_path_candidate:
		if has_node(head1_path):
			head_node = get_node(head1_path)
			is_have_head = true
			break
	if not is_have_head:
		printerr(name, "没有获取头节点")

## 初始化正常出战角色
func ready_norm():
	super()
	var is_have_head:=false
	for head1_path:NodePath in head1_path_candidate:
		if has_node(head1_path):
			head_node = get_node(head1_path)
			is_have_head = true
			break
	if not is_have_head:
		printerr(name, "没有获取头节点")
	curr_be_attack_status = init_be_attack_status
	## 若生成位置在斜面中,生成时修正斜面位置
	if is_instance_valid(Global.main_game.main_game_slope):
		## 获取对应位置的斜面y相对位置
		var slope_y_first = Global.main_game.main_game_slope.get_all_slope_y(global_position.x)
		move_y_zombie(slope_y_first)
	## 僵尸普通攻击组件连接信号
	#if attack_component is AttackComponentZombieNorm:
		### 攻击组件是否攻击梯子下僵尸
		#attack_component.init_attack_component(is_ignore_ladder)
	## 攻击的检测组件更新是否可以攻击梯子下的植物，是否忽略梯子
	attack_component.detect_component.is_attack_ladder_plant = is_ignore_ladder
	## 两栖类僵尸在水路时变化
	if Global.character_registry.get_zombie_info(zombie_type, CharacterRegistry.ZombieInfoAttribute.ZombieRowType) == CharacterRegistry.ZombieRowType.Both:
		if body_change_on_pool != null:
			zombie_row_type_both_body_update()

	## 舞王僵尸会报错，当前帧最后调用
	call_deferred("judge_battlefield_update_speed")

## 两栖类僵尸body变化
func zombie_row_type_both_body_update():
	## 水路时body变化
	if curr_zombie_row_type == CharacterRegistry.ZombieRowType.Pool:
		for sprite_path in body_change_on_pool.sprite_appear:
			var sprite = get_node(sprite_path)
			sprite.visible = true

		for sprite_path in body_change_on_pool.sprite_disappear:
			var sprite = get_node(sprite_path)
			sprite.visible = false
	else:

		for sprite_path in body_change_on_pool.sprite_appear:
			var sprite = get_node(sprite_path)
			sprite.visible = false

		for sprite_path in body_change_on_pool.sprite_disappear:
			var sprite = get_node(sprite_path)
			sprite.visible = true

#region 宽屏下僵尸是否在战场外
## 判断是否在战场的计时器，每0.3秒判断一次
var judge_battlefield_timer:Timer
## 进入战场信号
signal signal_enter_battlefield

## 僵尸判断宽屏战场外移动加速
func judge_battlefield_update_speed():
	if global_position.x >= 800:
		## 初始化角色速度
		update_speed_factor(2, E_Influence_Speed_Factor.OutBattlefield)
		judge_battlefield_timer = Timer.new()
		judge_battlefield_timer.name = "judge_battlefield_timer"
		judge_battlefield_timer.wait_time = 0.3
		judge_battlefield_timer.one_shot = false
		judge_battlefield_timer.timeout.connect(_on_judge_battlefield_timer_timeout)
		add_child(judge_battlefield_timer)
		judge_battlefield_timer.start()
		## 等待进入战场
		await signal_enter_battlefield
		update_speed_factor(1, E_Influence_Speed_Factor.OutBattlefield)

func _on_judge_battlefield_timer_timeout():
	#print("判断一次是否进入战场")
	if global_position.x < 800:
		signal_enter_battlefield.emit()
		judge_battlefield_timer.queue_free()

#endregion

## 初始化正常出战角色信号连接
func ready_norm_signal_connect():
	super()
	## 入场音效相关
	if not sfx_enter_name.is_empty():
		## 入场音效
		sfx_enter = SoundManager.play_character_SFX(sfx_enter_name)
		## 同一帧多次播放同一音效时不播放新音效
		if sfx_enter:
			is_sfxing = true
			sfx_enter.finished.connect(func():is_sfxing = false)
			hp_component.signal_hp_component_death.connect(_stop_sfx_enter)

	hp_component.signal_zombie_hp_loss.connect(func(hp_loss:int): signal_zombie_hp_loss.emit(hp_loss, curr_wave))
	## 角色死亡时禁用攻击组件
	hp_component.signal_hp_component_death.connect(attack_component.disable_component.bind(ComponentNormBase.E_IsEnableFactor.Death))
	## 攻击组件
	attack_component.signal_change_is_attack.connect(move_component.update_move_factor.bind(move_component.E_MoveFactor.IsAttack))
	attack_component.signal_change_is_attack.connect(change_is_attack)
	hurt_box_component = hurt_box_component as HurtBoxComponentZombie
	## 攻击时受击组件
	attack_component.signal_change_is_attack.connect(hurt_box_component.change_area_attack_appear)

	## 死亡时取消黄油
	hp_component.signal_hp_component_death.connect(death_stop_butter)

	## 血量状态变化组件
	hp_component.signal_hp_loss.connect(hp_stage_change_component.judge_body_change)
	## 防具血量状态变化组件
	hp_component.signal_hp_armor1_loss.connect(hp_stage_change_component.judge_body_change_armor.bind(true))
	hp_component.signal_hp_armor2_loss.connect(hp_stage_change_component.judge_body_change_armor.bind(false))

	## 当前动画结束时，移动组件改变移动状态
	anim_component.signal_animation_finished.connect(move_component._on_animation_finished)

	## 被魅惑信号
	signal_character_be_hypno.connect(hurt_box_component.owner_be_hypno)
	signal_character_be_hypno.connect(attack_component.owner_be_hypno)
	signal_character_be_hypno.connect(move_component._walking_start)

	## 游泳信号
	swim_box_component.signal_change_is_swimming.connect(change_is_swimming)

	## 铁器防具
	match iron_type:
		IronType.IronArmor1:
			hp_component.signal_armor1_death.connect(func():iron_type=IronType.Null)
		IronType.IronArmor2:
			hp_component.signal_armor2_death.connect(func():iron_type=IronType.Null)

	# 常规死亡掉落只抽取银币、金币和钻石。
	hp_component.signal_hp_component_death.connect(drop_item_component.drop_coin)

	## 移动僵尸本体y位置,修改对应检测层面节点位置
	move_component.signal_move_body_y.connect(move_y_zombie)

	## 对移动速度影响,只对速度移动模式生效
	signal_update_speed.connect(move_component.owner_update_speed)
	## 对攻击影响,
	signal_update_speed.connect(attack_component.owner_update_speed)

## 初始化展示角色
func ready_show():
	super()
	move_component.disable_component(ComponentNormBase.E_IsEnableFactor.InitType)

## 改变攻击状态攻击
func change_is_attack(value:bool):
	is_attack = value

## 更新移动方向修正(斜面时使用)
func update_move_dir_y_correct(move_dir_y_correct_slope:Vector2):
	#print("更新移动方向:", move_dir)
	move_component.move_dir_y_correct_slope = move_dir_y_correct_slope


## 角色移动y值(本体移动,同时修改检测层面的节点)
func move_y_zombie(move_y:float):
	position.y += move_y
	for n in node2d_detect_in_slope:
		n.position.y -= move_y

## 改变游泳状态,切换动画时0.2秒过度时间停止移动
func change_is_swimming(value:bool):
	is_swimming = value
	move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsSwimingChange)
	await get_tree().create_timer(0.2).timeout
	move_component.update_move_factor(false, MoveComponent.E_MoveFactor.IsSwimingChange)
	shadow.visible = not value

#region 僵尸受伤、死亡、
## 角色死亡
func character_death():
	_capture_tier_death_state()
	super()
	hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	swim_box_component._on_owner_is_death()
	#attack_component.queue_free()

## 僵尸死亡后逐渐透明，最后删除节点
func _fade_and_remove():
	var tween = create_tween()  # 自动创建并绑定Tween节点
	tween.tween_property(self, "modulate:a", 0.0, 1.0)  # 1秒内透明度降为0
	tween.tween_callback(queue_free)  # 动画完成后删除僵尸

## 死亡不消失(海草\TODO:小推车)
func character_death_not_disappear():
	hp_component.Hp_loss_death(false)

## 死亡直接消失
func character_death_disappear():
	_capture_tier_death_state()
	is_death = true
	is_can_death_language = false
	hp_component.Hp_loss_death(false)
	queue_free()

## 被小推车碾压
func be_mowered_run(lawn_mover:LawnMover):
	## 取消亡语
	is_can_death_language = false
	## 首先死亡无掉落
	hp_component.Hp_loss_death(false)
	## 禁用移动组件 停止移动
	move_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	## 停止动画
	anim_component.stop_anim()

	var zombie_death_bomb:ZombieDeathBomb = get_node_or_null("Body/ZombieDeathBomb")
	if zombie_death_bomb != null:
		zombie_death_bomb.activate_it()
	else:
		await be_mowered_run_anim_norm(lawn_mover)

	queue_free()



## 被小推车碾压动画(普通)
func be_mowered_run_anim_norm(lawn_mover:LawnMover):
	## 先掉落防具
	hp_component = hp_component as HpComponentZombie
	if hp_component.curr_hp_armor1 != 0:
		hp_stage_change_component.judge_body_change_armor(0, 0, true, true)
	if hp_component.curr_hp_armor2 != 0:
		hp_stage_change_component.judge_body_change_armor(0, 0, true, false)

	## 修改本体掉落物（手和头）
	var all_node_drop :Array[ZombieDropBase] = hp_stage_change_component.get_all_body_change()
	for node_drop in all_node_drop:
		node_drop.visible = false
		node_drop.reparent(self)

	## 身体被压扁
	var tween_be_mowered_run:Tween = create_tween()
	tween_be_mowered_run.set_parallel()
	tween_be_mowered_run.tween_property(body, "rotation_degrees", 90, 0.25)
	tween_be_mowered_run.tween_property(body, "scale", Vector2(0.5, 1), 0.25)

	await tween_be_mowered_run.finished
	body.visible = false

	## 掉落本体掉落物
	for node_drop in all_node_drop:
		node_drop.visible = true
		node_drop.acitvate_it_on_ground(lawn_mover.global_position.x)
		SoundManager.play_character_SFX("limbs_pop")
		await get_tree().create_timer(0.1).timeout


## 角色在泳池中死亡,泳池死亡动画调用
func in_water_death_start():
	var tween = create_tween()
	# 仅移动y轴，在1.5秒内下移200像素
	tween.tween_property(body, "position:y", body.position.y + 80, 2)
	#swim_box_component.in_water_death_start()

## 被水草缠住,
func be_grap_in_pool():
	attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	anim_component.stop_anim()
	move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsDeath)

## 承受 [param attack_value] 点爆炸伤害，返回本次实际击杀的僵尸。
## [param is_cherry_bomb] 为 true 时，普通致死爆炸使用原版灰烬演出。
## [param armor_multiplier] 只传递装备防具倍率，不改变灰烬、穿透与转伤行为。
## [param hit_scope] 可观察并去重同一爆炸的实际承伤者。
func be_bomb(attack_value: int, is_cherry_bomb: bool = false, armor_multiplier: float = 1.0,
		hit_scope: CombatHitScope = null) -> Zombie000Base:
	is_can_death_language = false
	var scope: CombatHitScope = hit_scope # 灰烬爆炸明确属于烧死，代伤者也接收同一来源。
	if scope == null and is_cherry_bomb:
		scope = CombatHitScope.new()
	var previous_cause: CombatHitScope.DeathCause = scope.death_cause if scope != null else CombatHitScope.DeathCause.NORMAL # 不污染调用方复用的群组。
	if is_cherry_bomb:
		scope.death_cause = CombatHitScope.DeathCause.FIRE
	var casualty: Zombie000Base = (hp_component as HpComponentZombie).apply_hit(
		attack_value, BulletRegistry.AttackMode.Penetration, false, false, true, armor_multiplier,
		0, -1, null, scope) # 可能是承受转移伤害的保护者。
	if scope != null:
		scope.death_cause = previous_cause
	if is_death and not _preserves_blast_death_animation():
		## 在在灰烬动画条件下
		if is_cherry_bomb and (not is_swimming or not curr_be_attack_status != E_BeAttackStatusZombie.IsDownGround):
			charred_component.play_charred_anim()
		queue_free()
	set_deferred("is_can_death_language", true)
	return casualty


## 返回致死爆炸是否保留物种自身的死亡演出。
func _preserves_blast_death_animation() -> bool:
	return false

## 被大嘴花吃
func be_chomper_eat(attack_value:int):
	is_can_death_language = false
	hp_component.Hp_loss(attack_value,BulletRegistry.AttackMode.Penetration, false, false)
	if is_death:
		queue_free()
	#await get_tree().process_frame
	set_deferred("is_can_death_language", true)

## 被倭瓜压
func be_squash(attack_value:int=1800):
	is_can_death_language = false
	hp_component.Hp_loss(attack_value,BulletRegistry.AttackMode.Penetration, false, false)
	if is_death:
		queue_free()
	#await get_tree().process_frame
	set_deferred("is_can_death_language", true)

#endregion
## 铁器被吸走
## 非一类防具和非二类防具需重写该函数
func be_magnet_iron():
	match iron_type:
		IronType.IronArmor1:
			hp_component.apply_unblocked_loss(hp_component.curr_hp_armor1, BulletRegistry.AttackMode.Norm, false, false)
		IronType.IronArmor2:
			hp_component.apply_unblocked_loss(hp_component.curr_hp_armor2, BulletRegistry.AttackMode.Norm, false, false)
		IronType.IronItem:
			loss_iron_item()

## 失去铁器道具的影响,对应子类继承重写
func loss_iron_item():
	iron_node.visible = false
	iron_type = IronType.Null

## 被吹走,在空中的僵尸被三叶草吹时调用
func be_blow_away():
	pass


## 僵尸从墓碑出现
func zombie_up_from_tombstone(anim_multiply:float):
	update_speed_factor(0.0, Character000Base.E_Influence_Speed_Factor.HammerZombieSpeed)
	await zombie_up_from_ground(1/anim_multiply)
	## 从地下出来后恢复动画
	update_speed_factor(anim_multiply, Character000Base.E_Influence_Speed_Factor.HammerZombieSpeed)

## 从地下出来
func zombie_up_from_ground(up_time:float = 1.0):
	is_body_up_from_ground = true
	await body.zombie_body_up_from_ground(up_time)
	is_body_up_from_ground = false

## 跳跃被高坚果停止
func jump_be_stop(_plant:Plant000Base):
	pass


#region 眩晕
## 返回当前是否因眩晕而暂停行动，供独立于动画推进的攻击和位移读取。
func is_stunned() -> bool:
	return influence_speed_factors.get(E_Influence_Speed_Factor.Stun, 1.0) == 0.0


## 返回是否因眩晕、恐惧或抛起暂停攻击行为；移动只检查眩晕和强制轨迹，恐惧仍能逃跑。
func is_action_suspended() -> bool:
	return is_stunned() or (is_instance_valid(move_component) and (
		move_component.is_forced_airborne() or move_component.is_fleeing()))


## [param duration] 为负面效果入口验证过的游戏秒数；连续命中只延长当前剩余时间。
func be_stunned(duration: float) -> void:
	# 每个僵尸复用一个随场景暂停的计时器，由角色持有并随角色释放。
	var timer: Timer = all_timer[E_TimerType.Stun]
	if not is_instance_valid(timer):
		timer = GlobalUtils.create_new_timer_once(self, _end_stun)
		timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
		all_timer[E_TimerType.Stun] = timer
		signal_character_death.connect(_end_stun, CONNECT_ONE_SHOT)
	if timer.time_left < duration:
		timer.start(duration)
	if not is_stunned():
		update_speed_factor(0.0, E_Influence_Speed_Factor.Stun)


## 到期或死亡时解除眩晕，让其他速度因子和死亡动画继续生效。
func _end_stun() -> void:
	all_timer[E_TimerType.Stun].stop()
	if is_stunned():
		update_speed_factor(1.0, E_Influence_Speed_Factor.Stun)
#endregion


#region 黄油
## 黄油糊脸
##[butter_time:float]:黄油糊脸时间
func be_butter(butter_time:float=4):
	if not is_death:
		## 黄油节点
		if not is_instance_valid(butter_splat):
			butter_splat = SceneRegistry.BUTTER_SPLAT.instantiate()
			# 将精灵添加到当前场景中
			add_child(butter_splat)
		butter_splat.visible = true
		butter_splat.global_position = head_node.to_global(Vector2(20, 10))

		## 更新速度
		update_speed_factor(0.0, E_Influence_Speed_Factor.Butter)
		if not is_instance_valid(all_timer[E_TimerType.Butter]):
			all_timer[E_TimerType.Butter] = GlobalUtils.create_new_timer_once(self, _on_butter_timer_timeout)

		all_timer[E_TimerType.Butter].start(butter_time)

## 死亡时停止黄油
func death_stop_butter():
	if is_instance_valid(butter_splat):
		_on_butter_timer_timeout()

## 黄油时间计时器结束
func _on_butter_timer_timeout() -> void:
	update_speed_factor(1.0, E_Influence_Speed_Factor.Butter)
	butter_splat.visible = false
#endregion

#region 僵尸吃大蒜换行
## 大蒜反应结束后，仍存活的僵尸开始换行。
func update_lane_on_eat_garlic():
	SoundManager.play_character_SFX("yuck")
	update_speed_factor(0.0, E_Influence_Speed_Factor.EatGarlic)
	await get_tree().create_timer(0.5, false).timeout
	if is_death or is_queued_for_deletion() or not is_inside_tree():
		return
	update_speed_factor(1.0, E_Influence_Speed_Factor.EatGarlic)
	update_lane()


## 选同类相邻行并更新战场登记。实际位移走移动组件，和击飞的斜坡修正相加。
func update_lane() -> void:
	var game: MainGameManager = Global.main_game # 只在当前战斗的僵尸行内切换。
	if is_death or is_queued_for_deletion() or not is_instance_valid(game) or not game.is_ancestor_of(self):
		return
	if not is_instance_valid(game.zombie_manager) or not is_instance_valid(move_component):
		return
	# 在修改行号和父节点前校验，载具被拒绝位移时也不会留下错误战场登记。
	if not move_component.can_receive_forced_displacement():
		return
	var rows: Array[ZombieRow] = game.zombie_manager.all_zombie_rows # 行索引与战斗登记一致。
	if lane < 0 or lane >= rows.size():
		return
	var available: Array[int] = [] # 能保持当前陆地或水路状态的相邻行。
	for neighbor: int in [lane - 1, lane + 1]: # 当前行的两侧候选。
		if neighbor >= 0 and neighbor < rows.size() and rows[neighbor].zombie_row_type == curr_zombie_row_type:
			available.append(neighbor)
	if available.is_empty():
		return
	var next_lane: int = available.pick_random() # 双侧可用时保持原有随机选择。
	var next_row: ZombieRow = rows[next_lane] # 目标行负责渲染层和战场登记。
	var row_offset: float = next_row.zombie_create_position.global_position.y \
		- rows[lane].zombie_create_position.global_position.y # 只改变行距，保留当前斜坡高度。
	lane = next_lane
	signal_lane_update.emit()

	# 换行时禁用攻击；移动组件完成换行后解除这一原因。
	attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Garlic)
	_reparent_with_action_timers(next_row)
	var finish: Callable = attack_component.enable_component.bind(ComponentNormBase.E_IsEnableFactor.Garlic) # 恢复大蒜暂时关闭的攻击。
	if not move_component.apply_forced_displacement(Vector2(0.0, row_offset), 1.0, 0.0, finish):
		finish.call()

## [param next_row] 为已验证的新行；可逆换父节点时保留动作计时器进度和手动暂停意图。
## SpeedTimer 的真正离树仍会停止；这里只恢复本次换行前实际在运行的计时器。
func _reparent_with_action_timers(next_row: ZombieRow) -> void:
	var saved: Array[Dictionary] = [] # 原生引信和攻击冷却使用正常倍率下的剩余动作秒数。
	for node: Node in find_children("*", "Timer", true, false): # 只收集 SpeedTimer，不改变普通场景计时器。
		var timer: SpeedTimer = node as SpeedTimer # 普通 Timer 不会执行自定义离树 stop。
		if timer != null and not timer.is_stopped():
			saved.append({"timer": timer, "remaining": timer.get_base_time_left(),
				"period": timer.base_wait_time, "paused": timer.manual_paused})
	is_changing_lane = true
	reparent(next_row)
	is_changing_lane = false
	for entry: Dictionary in saved: # 只恢复这次换行亲自暂停的任务，已经停止的动作不重启。
		var timer: SpeedTimer = entry["timer"] as SpeedTimer # 原节点仍属于本角色，不重建计时器。
		if not is_instance_valid(timer) or not timer.is_inside_tree() or is_death:
			continue
		var component: Node = timer.get_parent() # 迁移期间已禁用的攻击或爆炸组件不可被恢复计时重新启动。
		var disabled := false # 只尊重真实组件禁用，不把计时器自身的手动暂停误当作停止。
		while is_instance_valid(component) and component != self:
			if component is ComponentNormBase and not (component as ComponentNormBase).is_enabling:
				disabled = true
				break
			component = component.get_parent()
		if disabled:
			continue
		var remaining: float = float(entry["remaining"]) # 到期任务不以零秒错误重启整个周期。
		if remaining > 0.0:
			timer.manual_paused = bool(entry["paused"])
			timer.start_scaled(remaining)
			timer.base_wait_time = float(entry["period"])

#endregion


#region 梯子
## 梯子检测到僵尸时,僵尸爬过梯子
func start_climbing_ladder():
	move_component.start_ladder()

#endregion

#region 特殊场景状态
## 小僵尸大麻烦
func update_mini_zombie():
	random_speed_range *= 2
	## 舞王僵尸会改变符号,所有这么写
	scale = Vector2(
		0.5 * sign(scale.x),
		0.5 * sign(scale.y)
	)
	hp_component = hp_component as HpComponentZombie
	hp_component.update_mini_zombie_hp()
	hp_stage_change_component.update_mini_zombie_hp_stage_change()
	hurt_box_component.scale *= 2

#endregion
