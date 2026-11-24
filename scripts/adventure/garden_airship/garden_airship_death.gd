## 花园飞艇独占的死亡表现。只从真实致死和已脱落的纯表现取得交接。
extends "res://scripts/adventure/garden_airship/garden_airship_death_sweep.gd"

## 只识别由火箭小鬼当前独立死亡播放器创建的现有绘制节点。
const ROCKET_DEATH_SCRIPT: String = "res://scripts/character/zombie/rocket_imp/rocket_imp_death.gd"
## 与原活体喷气声相同，喷口附在死亡精灵继承的原图坐标。
const ROCKET_EXHAUST := Vector2(58.0, 38.0)
## 保留当前实体真正跨过死亡阈值前的惯性，消费后立刻移除。
const FATAL_VELOCITY: StringName = &"_airship_fatal_velocity"
## 按原资源登记一次的纯美术动画，随战局释放。
var _clips: Dictionary[Animation, Animation] = {}
## 局内飞行节点显式提供的爆炸和喷口熄火能力。
var _blasts: Node


## [param blasts] 属于同一实际战场，接收死亡外观的局部挂点。
func setup_blasts(blasts: Node) -> void:
	_blasts = blasts


## 只接入本场波次的真实敌人；其他关卡没有此节点或此订阅。
func _ready() -> void:
	set_process(false)
	var manager := get_parent().get_node_or_null(^"Manager/ZombieManager") as ZombieManager # 先于战斗根节点初始化阶段绑定。
	if manager != null:
		manager.signal_zombie_created.connect(_track_zombie)


## [param zombie] 已通过战场登记。死亡观察使用一次性生命期信号。
func _track_zombie(zombie: Zombie000Base) -> void:
	zombie.hp_component.before_death.connect(_before_fatal.bind(zombie), CONNECT_ONE_SHOT)
	zombie.signal_character_death.connect(_on_fatal.bind(zombie), CONNECT_ONE_SHOT)
	zombie.signal_zombie_death_residue.connect(_on_residue)


## 从 [param source] 读取原来正在移动的世界速度，控制停止后的死亡链不能改写它。
func source_velocity(source: Zombie000Base) -> Vector2:
	var known: Vector2 = source.get_meta(FATAL_VELOCITY, Vector2.INF) # 专用载具进入死亡时也沿用同一快照。
	if known.is_finite():
		return known
	var movement: MoveComponent = source.move_component # 普通行走、飞行与押运以各自的原生速率为基准。
	var parent_canvas := source.get_parent() as CanvasItem # 战斗行当前的世界坐标基。
	if parent_canvas == null or not is_instance_valid(movement) or not movement.is_move \
			or not movement.is_enabling or source.is_stunned():
		return Vector2.ZERO
	var horizontal: float = -movement.get_speed_mode_speed() * source.direction_x_root # 活体通常逆风向左。
	return parent_canvas.get_global_transform().basis_xform(Vector2(horizontal, 0.0))


## [param _cause] 已由生命组件确认。[param zombie] 特殊表现还未隐藏或释放。
func _before_fatal(_cause: CombatHitScope.DeathCause, zombie: Zombie000Base) -> void:
	if zombie.is_death or zombie.retiring_from_battle:
		return
	zombie.set_meta(FATAL_VELOCITY, source_velocity(zombie))
	if zombie.zombie_type == CharacterRegistry.ZombieType.Z041RocketImp:
		zombie.get_parent().child_entered_tree.connect(_on_rocket_visual.bind(zombie))


## [param zombie] 已走原生死亡入口和注销；同一帧的装备脱落和灰烬继续由原代码完成。
func _on_fatal(zombie: Zombie000Base) -> void:
	if not zombie.has_meta(FATAL_VELOCITY):
		return
	var velocity: Vector2 = zombie.get_meta(FATAL_VELOCITY) # 仍由原扣血路径提供，不求新的战斗位移。
	zombie.remove_meta(FATAL_VELOCITY)
	match zombie.zombie_type:
		CharacterRegistry.ZombieType.Z041RocketImp:
			var row: Node = zombie.get_parent() # 原死亡精灵已在发布死亡信号前进入这一行。
			var observer: Callable = _on_rocket_visual.bind(zombie) # 同步解除这次死亡的临时观察。
			if row.child_entered_tree.is_connected(observer):
				row.child_entered_tree.disconnect(observer)
		CharacterRegistry.ZombieType.Z034Fighter, CharacterRegistry.ZombieType.Z038ArbiterX, \
		CharacterRegistry.ZombieType.Z039CannonTurret, CharacterRegistry.ZombieType.Z040TransportAirship:
			pass
		_:
			_finish_fatal.call_deferred(zombie.get_instance_id(), velocity)


## [param zombie_id] 仅查仍存续的原生死亡演出，[param velocity] 保留受击前的世界速度。
func _finish_fatal(zombie_id: int, velocity: Vector2) -> void:
	var zombie := instance_from_id(zombie_id) as Zombie000Base # 灰烬和瞬间销毁已经由原演出入口处理。
	if not is_instance_valid(zombie) or not is_inside_tree() or zombie.retiring_from_battle or zombie.is_queued_for_deletion():
		return
	var weight: float = 0.48 # 普通身体惯性。
	match zombie.zombie_type:
		CharacterRegistry.ZombieType.Z025Imp:
			weight = 0.12
		CharacterRegistry.ZombieType.Z024Gargantuar:
			weight = 0.86
		CharacterRegistry.ZombieType.Z008Football, CharacterRegistry.ZombieType.Z005Bucket:
			weight = 0.66
	capture_body(zombie, weight, velocity)


## [param source] 的本体会在原时间线播放权威回调；复制的裁片只播放同一美术姿态。
## [param weight] 为类别惯性，[param velocity] 是死亡前世界速度，[param kind] 标记原演出类型。
## [param burst_id] 将次爆绑定到复制的纯外观。返回可见快照，预算拒绝时为空。
func capture_body(source: Zombie000Base, weight: float, velocity: Vector2,
		kind: StringName = &"body", burst_id: int = 0) -> Node2D:
	if not _can_start(kind):
		return null
	var body: Node2D = source.body # 实际命中帧，含摆动、装备状态和姿态。
	var snapshot: Node2D = Pose.capture(body, get_parent() as CanvasItem) # 纯精灵子树，无原实体脚本。
	if snapshot == null:
		return null
	var world_pose: Transform2D = body.global_transform # 相同战斗画布，不混用虚拟远景变换。
	var sweep: Sweep = _add_sweep(world_pose.origin, weight, velocity, kind, Pose.absolute_z(body)) # 阵亡当下即获得非零船尾速度。
	sweep.add_child(snapshot)
	snapshot.global_transform = world_pose
	sweep.visual = snapshot
	body.hide()
	if is_instance_valid(source.shadow):
		source.shadow.hide()
	detached.emit(world_pose.origin, sweep, weight)
	if burst_id > 0 and is_instance_valid(_blasts):
		_blasts.track_burst(burst_id, snapshot)
	if kind == &"body":
		_start_body_clip(source, snapshot)
	return snapshot


## [param zombie] 仍持有其原始动画资源。[param snapshot] 接续其中实际的纯美术倒地轨道。
func _start_body_clip(zombie: Zombie000Base, snapshot: Node2D) -> void:
	if not is_instance_valid(zombie) or not is_instance_valid(snapshot):
		return
	var native := zombie.get_node_or_null(^"AnimationPlayer") as AnimationPlayer # 逐帧物种已经用原死动画的帧和进度起步。
	if native == null:
		return
	var clip: StringName = _death_clip(zombie, native) # 避免复制攻防动画回调或重放预览姿态。
	if clip.is_empty():
		return
	var original: Animation = native.get_animation(clip) # 只读取统一动画库中的实际资源。
	var animation: Animation = _clips.get(original) # 大批同种死亡共用一次过滤结果。
	if animation == null:
		animation = Pose.visual_clip(original, snapshot)
		_clips[original] = animation
	if animation.get_track_count() == 0:
		return
	var library := AnimationLibrary.new() # 独立播放器不连接原战场信号。
	library.add_animation(&"death", animation)
	var player := AnimationPlayer.new() # 下一次引擎表现更新才接续倒地帧。
	player.add_animation_library(&"", library)
	snapshot.add_child(player)
	if zombie is Zombie001Norm:
		_pose_death_arms(snapshot, zombie.zombie_type)
	player.play(&"death", -1.0, zombie.anim_component.animation_origin_speed)


## 返回 [param source] 和 [param player] 所采用的现有死亡剪辑名，空名称表示该物种无此轨道。
func _death_clip(source: Zombie000Base, player: AnimationPlayer) -> StringName:
	if source is Zombie001Norm:
		var choices: Array[StringName] = [&"Zombie_death", &"Zombie_death2", &"Zombie_superlongdeath"] # 复用原出生时选定的动作。
		var selected: StringName = choices[clampi(source.death_status - 1, 0, choices.size() - 1)] # 不再消费战斗随机流。
		if player.has_animation(selected):
			return selected
	for clip: StringName in player.get_animation_list(): # 其他经典物种各有自己的倒地轨。
		if Pose.is_death_clip(clip):
			return clip
	return &""


## 在 [param snapshot] 重现普通骨骼动画的纯可见手臂切换，[param type] 对应原持旗和铁门的变体。
func _pose_death_arms(snapshot: Node2D, type: CharacterRegistry.ZombieType) -> void:
	var rig := snapshot.get_node_or_null(^"Body/BodyCorrect") as Node2D # 已移除死亡动画中的方法轨。
	if rig == null:
		return
	var arm := rig.get_node_or_null(^"Anim_innerarm") as Node2D # 原死亡关键帧从外手切到里手。
	if arm != null:
		arm.show()
	var obsolete: Array[NodePath] = [] # 各物种仅隐藏自己的持物裁片。
	if type == CharacterRegistry.ZombieType.Z002Flag:
		obsolete.assign([^"Zombie_flaghand", ^"Zombie_innerarm_screendoor"])
	elif type == CharacterRegistry.ZombieType.Z007ScreenDoor:
		obsolete.assign([^"Zombie_innerarm_screendoor", ^"Zombie_innerarm_screendoor_hand", ^"Zombie_outerarm_screendoor"])
	for path: NodePath in obsolete: # 美术节点缺失时保留实际源快照。
		var held := rig.get_node_or_null(path) as Node2D # 对应原动画方法中的一只手。
		if held != null:
			held.hide()


## [param visual] 是真正由 [param zombie] 的受击入口新建的独立坠落精灵。
func _on_rocket_visual(visual: Node, zombie: Zombie000Base) -> void:
	var script: Script = visual.get_script() # 排除同一行另外创建的存活角色和碎片。
	if not visual is AnimatedSprite2D or script == null or script.resource_path != ROCKET_DEATH_SCRIPT:
		return
	var velocity: Vector2 = source_velocity(zombie) # 仍在原死亡通知之前，惯性没有被消费。
	_detach_rocket.call_deferred(visual.get_instance_id(), velocity)


## [param visual_id] 识别现有坠落精灵；[param velocity] 是受击前速度。只在真实交接时从原喷口短熄火。
func _detach_rocket(visual_id: int, velocity: Vector2) -> void:
	var visual := instance_from_id(visual_id) as Node2D # 已经由原序列退出的对象没有附加效果。
	if not is_instance_valid(visual):
		return
	var sweep: Node2D = sweep_visual(visual, 0.12, velocity, &"rocket") # 原坠落动作、速度与 R5 接管入口。
	if sweep == null or not is_instance_valid(_blasts):
		return
	var origin: Vector2 = visual.to_global(ROCKET_EXHAUST) # 保留喷焰已烘焙的死亡动画，只加短促火星与尾雾。
	var id: int = _blasts.start_burst(&"rocket", origin, 0.24, velocity, sweep.z_index + 1)
	var pieces: Array[Node2D] = [] # 喷口只追踪原死亡精灵，没有独立爆炸片体。
	_blasts.track_burst(id, visual, PackedVector2Array(), pieces, ROCKET_EXHAUST)


## [param visual] 是真死亡的灰烬、装备或肢体，[param velocity] 为原初始抛速的世界分量。
func _on_residue(visual: Node2D, velocity: Vector2) -> void:
	if visual is CharredComponent:
		sweep_visual(visual, 0.12, velocity, &"ashes")
	else:
		sweep_visual(visual, 0.08, velocity, &"fragment")
