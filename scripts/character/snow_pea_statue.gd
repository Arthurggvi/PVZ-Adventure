## 斯卡蒂冰雕是独立敌方受击实体。原僵尸当场完成死亡，冰雕不进入波次计数。
extends EnemyStructureBase
class_name SnowPeaStatue

## 冰雕的标准设施场景；只有斯卡蒂致死时才需要。
const SCENE_PATH: String = "res://scenes/character/snow_pea_statue.tscn"
## 生成冰雕的原始发射，保留棱锥的完整来源。
var _shot: SnowPeaShot
## 生成冰雕的根弹接触序号，只拒绝同一接触派生的冷萃。
var _contact: int
## 16枚棱锥相对于冰雕的爆心，来自原真实受击区域。
var _burst_offset: Vector2
## 原画冰壳用于读取可见范围，不复制角色动画或状态。
var _pose: SnowPeaStatuePose
## 实际承伤只播放一次破碎，防止同帧的重复信号叠出多份画布与棱锥。
var _fractured: bool = false

## [param zombie] 即将在原生路由中死亡；[param shot] 与 [param contact] 唯一标识该次接触。
## 在死亡信号前采集姿势与受击几何，入树等待当前物理冲刷和致死事务完成。
static func capture(zombie: Zombie000Base, shot: SnowPeaShot, contact: int) -> void:
	if zombie.is_hypno or not zombie.can_receive_cold() or not zombie.can_receive_negative_effects() \
			or not zombie.hurt_box_component.is_enabling or zombie.is_queued_for_deletion() \
			or zombie.character_init_type != Character000Base.E_CharacterInitType.IsNorm:
		return
	var scene := load(SCENE_PATH) as PackedScene # 不引入注册表场景依赖。
	var statue := scene.instantiate() as SnowPeaStatue # 未入树时填充纯数据和碰撞形状。
	var feet: Vector2 = zombie.global_position # 独立设施保持原处，不随尸体死亡动画移动。
	statue._shot = shot
	statue._contact = contact
	statue.lane = zombie.lane
	statue.z_index = zombie.z_index
	statue._copy_collision(zombie, feet)
	statue._copy_pose(zombie, feet)
	statue._mount.call_deferred(feet, weakref(zombie))

## [param shot] 与 [param contact] 为待结算溅射的来源，只排除生成冰雕的同一次撞击。
func was_created_by(shot: SnowPeaShot, contact: int) -> bool:
	return _shot == shot and _contact == contact

## [param zombie] 的原生真实受击形状以 [param feet] 为冰雕局部原点。
func _copy_collision(zombie: Zombie000Base, feet: Vector2) -> void:
	var source: Area2D = zombie.hurt_box_component.hurt_box_real # 保留原姿态的受击尺寸。
	var frame := Transform2D(0.0, -feet) # 世界变换转成冰雕局部坐标。
	var detection := get_node("HurtBoxComponent/HurtBoxDetection") as Area2D # 攻击组件可正常索敌。
	var hurt := get_node("HurtBoxComponent/HurtBoxReal") as Area2D # 原生子弹和范围攻击共用此区域。
	var fallback := hurt.get_node("CollisionShape2D") as CollisionShape2D # 没有可用形状时保留原生胶囊。
	_burst_offset = source.global_position - feet + fallback.position
	for node: Node in source.get_children(): # 只捕获活动伤害形状，不继承僵尸的动态组件。
		var original := node as CollisionShape2D # 形状资源可共享，变换单独保存。
		if original == null or original.disabled or original.shape == null:
			continue
		var copy := CollisionShape2D.new() # 普通设施使用自身静态形状。
		copy.shape = original.shape
		copy.transform = frame * original.global_transform
		if is_instance_valid(fallback):
			_burst_offset = copy.position
			fallback.free()
			fallback = null
		hurt.add_child(copy)
		detection.add_child(copy.duplicate())
	if is_instance_valid(fallback):
		detection.add_child(fallback.duplicate())

## [param zombie] 为当前姿势来源；[param feet] 将其可见原画定位到冰雕局部。
func _copy_pose(zombie: Zombie000Base, feet: Vector2) -> void:
	var display := get_node("Body") as BodyCharacter # 只挂静态绘制节点，不复制动画和角色脚本。
	_pose = SnowPeaStatuePose.new()
	_pose.capture(zombie.body, feet)
	display.add_child(_pose)

## 在安全阶段使用 [param feet] 安装设施；[param original] 只在原死亡事务结束后隐藏原身体。
func _mount(feet: Vector2, original: WeakRef) -> void:
	if not _shot.battle.is_active():
		free()
		return
	var corpse := original.get_ref() as Zombie000Base # 原僵尸可能已由死亡动画直接释放。
	if is_instance_valid(corpse):
		if not corpse.is_death:
			free()
			return
		corpse.body.hide()
		corpse.shadow.hide()
	position = _shot.battle.game.items.to_local(feet)
	_shot.battle.game.items.add_child(self)
	SnowPeaStatueBurst.spawn(_shot.battle, feet, _pose.get_pose_bounds(), false, z_index)

## [param _delta] 不推进冰雕寿命；当前轮次或阶段失效时撤销设施。
func _physics_process(_delta: float) -> void:
	if not _shot.battle.is_active():
		hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
		queue_free()

## 实际伤害才触发破碎。直接清场和无伤命中不进入此入口。
## [param loss] 为原生生命组件报告的实际伤害。
func _on_combat_health_lost(loss: int) -> void:
	if loss > 0 and not _fractured and _shot.battle.is_active():
		_fractured = true
		SnowPeaStatueBurst.spawn.call_deferred(_shot.battle, global_position, _pose.get_pose_bounds(), true, z_index)
		_release_prisms.call_deferred(_shot, to_global(_burst_offset), lane)

## [param shot]、[param position] 与 [param source_lane] 已冻结，不依赖已碎的冰雕。
static func _release_prisms(shot: SnowPeaShot, position: Vector2, source_lane: int) -> void:
	if not shot.battle.is_active():
		return
	var count: int = int(shot.loadout.number(&"skadi", &"prism_count")) # 每次固定十六条空间弹道。
	for index: int in range(count): # 等分圆周，每颗独立去重并按自身碰撞结算。
		shot.emit_projectile(position, Vector2.from_angle(TAU * index / count), source_lane, true)
