## 原生星弹按发射快照取得转职能力，保留地形和防具碰撞入口。
extends BulletLinear000Base
class_name Bullet008Star

## 独立的弹色与命中效果。派生弹不调用植物的攻击回调。
enum Kind { GOLD, VIOLET, BLUE, RED }
## 同一攻击快照的卡牌词条。贯穿与流光只作用于普通星弹。
enum Trait { AIM = 1, PIERCE = 2, REFRACT = 4, STREAM = 8 }
## 瞄准时使用战场公用的真实受击点和候选资格。
const AimIndex = preload("res://scripts/adventure/research/starfruit_aim_index.gd")
## 原生和转职星弹把退场传给同一个战场画布。
const StarVisual = preload("res://scripts/adventure/research/starfruit_visual.gd")
## 从出射开始累计的游戏秒数。
const AIM_DELAY: float = 0.2
## 锁定后每秒最大转角，星弹在半个可读的弧线内完成调头。
const TURN_SPEED: float = 22.0
## 四个弹种按枚举使用共享的主色。
const TINTS := [Color(1.0, 0.76, 0.22), Color(0.77, 0.39, 1.0),
	Color(0.27, 0.82, 1.0), Color(1.0, 0.29, 0.39)]
## 弹身深色星形轮廓，在草地、水和高亮效果上仍可辨认。
static var _edge: PackedVector2Array = _star_points(12.5, 6.0)
## 弹身主体形状，各星只改变颜色和画布旋转。
static var _face: PackedVector2Array = _star_points(10.6, 5.0)
## 不规则高光面在旋转时形成星形切面。
static var _facet := PackedVector2Array([Vector2(0,-9), Vector2(3,-2), Vector2(7,-2),
	Vector2(0,3), Vector2(-5,1), Vector2(-1,-2)])

## 战场容器拥有实际索敌和视觉收据。
var _runtime: Node2D
## 原战场、卡牌伤害和攻击来源的冻结快照。
var _shot: RepeaterShotContext
## 同一出手派生星弹时仍读取冻结的卡牌词条。
var _traits: int = 0
## 当前星弹类型。
var kind: Kind = Kind.GOLD
## 只有普通贯穿星使用接触时钟。
var _flow: bool = false
## 从弹口开始的瞄准倒数，负数表示已经执行或无需锁定。
var _aim_left: float = -1.0
## 锁定目标失效时清空，不另作全场查询。
var _target: Character000Base
## 缓存形状节点，跟踪时直接取实际碰撞中心。
var _target_point: Node2D
## 只在状态或折射需要确认真正承伤者时写入回执。
var _receipt: Dictionary = {}
## 旧的重叠受击区可能同属一个角色，用当前接触集合去重。
var _contacts: Dictionary[int, bool] = {}
## 红星的引爆回调在同一颗巨星的全部溅射弹之间共享。
var _detonation: Dictionary
## 本弹主色，以及流光状态使用的同色拽尾。
var _tint: Color
## 原生杨桃显式启用退场，其他物种衍生的星弹继续使用自己的演出。
var _native_exit: bool = false
## 只保留已创建的共用画布，物理碰撞时无需挂载节点。
var _exit_visual: StarVisual
## 撞地通知内保存坡面的法线，用于使余光回溅至碰撞面外。
var _surface_normal: Vector2 = Vector2.ZERO
## 原生弹身在本弹就绪时缓存，物理更新不再查找节点路径。
@onready var _face_sprite: Sprite2D = $Body/BulletBody

## 配置 [param runtime]、[param shot]、[param traits] 和 [param color_kind]，红星共用 [param detonation]。
## [param visual] 已挂载于原战场，退场时无需再创建节点。
func configure_promotion(runtime: Node2D, shot: RepeaterShotContext, traits: int, color_kind: Kind,
		detonation: Dictionary, visual: StarVisual) -> void:
	_runtime = runtime
	_exit_visual = visual
	_shot = shot
	_traits = traits
	kind = color_kind
	_detonation = detonation
	_tint = TINTS[kind]
	if kind == Kind.RED and detonation.has("landing_targets"):
		_promotion_hit_ids = detonation["landing_targets"] # 两圈共享已结算坠落的名单，出射不会在碰撞体内立刻被吃光。
	if _traits & Trait.AIM:
		_aim_left = AIM_DELAY
	if kind == Kind.GOLD and (_traits & Trait.PIERCE) != 0:
		bullet_mode = BulletRegistry.AttackMode.Penetration
		max_attack_num = -1
		unique_target_hits = true
		_flow = (_traits & Trait.STREAM) != 0
	if _flow:
		_tint = Color(0.46, 0.99, 0.72)

## 原生杨桃在弹体入树前绑定 [param visual]，保留原弹身与旋转。
func enable_native_exit(visual: StarVisual) -> void:
	_native_exit = true
	_exit_visual = visual
	_tint = TINTS[Kind.GOLD]

## 转职弹使用同样的受击区与影子，绘制命中时省去独立粒子节点和旋转 Tween。
func _ready() -> void:
	if _native_exit or _runtime != null:
		bullet_effect.is_bullet_effect = false
	if _runtime == null:
		super()
		return
	is_rotate = false
	trigger_be_attack_sfx = false
	type_bullet_SFX = SoundManagerClass.TypeBulletSFX.Null
	super()
	_face_sprite.texture = null
	_face_sprite.draw.connect(_draw_face)
	body.draw.connect(_draw_trail)
	_face_sprite.queue_redraw()
	body.queue_redraw()

## [param delta] 为游戏步长。到时只取一次最近目标，随后只跟踪其碰撞点。
func _physics_process(delta: float) -> void:
	super(delta)
	if _runtime == null or is_queued_for_deletion():
		return
	if _aim_left >= 0.0:
		_aim_left -= delta
		if _aim_left <= 0.000001:
			_aim_left = -1.0
			_runtime.lock_star(self, _promotion_hit_ids)
	if is_instance_valid(_target):
		if not AimIndex.ground_target(_target) or not is_instance_valid(_target_point) \
				or _promotion_hit_ids.has(_target.get_instance_id()):
			_target = null
			_target_point = null
		else:
			var desired: Vector2 = get_parent().to_local(_target_point.global_position) - position # 方向与线性移动组件同空间。
			var turn: float = clampf(direction.angle_to(desired), -TURN_SPEED * delta, TURN_SPEED * delta) # 渐变转角。
			direction = direction.rotated(turn)
			body.rotation = direction.angle()
	_face_sprite.rotation += delta * (9.0 if kind == Kind.BLUE else 6.2)

## 缓存本弹在0.2秒时选出的 [param target] 和 [param point]。
func set_aim_target(target: Character000Base, point: Node2D) -> void:
	_target = target
	_target_point = point

## [param area] 为真实受击区。流光只将当前有接触的弹加入定频时钟。
func _on_area_2d_attack_area_entered(area: Area2D) -> void:
	if is_queued_for_deletion():
		return
	if _flow and _can_attack_character(area.owner as Character000Base):
		_runtime.track_flow(self)
	else:
		if area.owner is Slope:
			_surface_normal = area.owner.normal_vector_slope
		super(area)
		_surface_normal = Vector2.ZERO

## 向共用画布记录 [param cause] 所指的真实终点。物理碰撞和流光结算随本帧回收一起结束。
func _finish_projectile(cause: ExitCause) -> void:
	if is_instance_valid(_exit_visual) and not is_queued_for_deletion() and _exit_visual.can_show_exit(global_position):
		var host := get_parent() as Node2D # 弹体方向由真实容器坐标转换，不使用相机旋转。
		var heading: Vector2 = host.global_transform.basis_xform(direction).normalized() # 拖尾沿实际世界弹道。
		_exit_visual.add_projectile_exit(global_position, heading, _surface_normal, _face_sprite.global_rotation,
			_tint, _trail_length(), cause)
	super(cause)

## 原生护框限制和 [param check_lane] 保持有效，转职星不再攻击已转投植物的 [param enemy]。
func _can_attack_character(enemy: Character000Base, check_lane: bool = true) -> bool:
	return super(enemy, check_lane) and (_runtime == null or (not enemy.is_hypno \
		and (kind != Kind.RED or not _promotion_hit_ids.has(enemy.get_instance_id()))))

## 结算一次接触样本。返回是否仍有能结算的重叠目标。
func tick_flow_contacts() -> bool:
	if not is_attack_active() or is_queued_for_deletion():
		return false
	_contacts.clear()
	for area: Area2D in area_2d_attack.get_overlapping_areas(): # 只走原生监控的真实接触列表。
		var target := area.owner as Character000Base # 多个碰撞形状归并到同一受击实体。
		if not _can_attack_character(target):
			continue
		var id: int = target.get_instance_id() # 同步伤害回调可能移除角色，先登记。
		if _contacts.has(id):
			continue
		_contacts[id] = true
		var original: int = attack_value # 每一跳只叠一次原生伤害上下文。
		if attack_context != null:
			attack_value = attack_context.modify_damage(original, target)
		last_impact_casualty = null
		_attack_enemy(target)
		attack_value = original
		_shot.on_kill(last_impact_casualty)
	return not _contacts.is_empty()

## 流光的高频命中绕过每次受击闪白，仍沿用实际防具与代伤路径。
func _attack_zombie(zombie: Zombie000Base) -> void:
	if not _flow:
		super(zombie)
		return
	var armor: float = attack_context.armor_multiplier if attack_context != null else 1.0 # 与普通星同一防具倍率。
	last_impact_casualty = _apply_zombie_impact(zombie, bullet_mode, armor, Vector2i(0, -1))

## [param enemy] 保留僵王受击窗口，并在普通状态允许时叠加劣化或引爆值。
func _attack_enemy(enemy: Character000Base) -> void:
	super(enemy)
	if _runtime != null and is_instance_valid(enemy) and enemy is ZB000Base:
		_apply_status(enemy)

## [param zombie]、[param mode]、[param armor]、[param bonus] 交给防具路由；状态授予真正承伤者。
func _apply_zombie_impact(zombie: Zombie000Base, mode: BulletRegistry.AttackMode, armor: float,
		bonus: Vector2i) -> Zombie000Base:
	if _runtime == null:
		return super(zombie, mode, armor, bonus)
	if kind == Kind.GOLD and (_traits & (Trait.PIERCE | Trait.REFRACT)) == 0:
		return super(zombie, mode, armor, bonus)
	_receipt.clear()
	var casualty: Zombie000Base = (zombie.hp_component as HpComponentZombie).apply_hit(
		attack_value, mode, true, false, true, armor, bonus.x, bonus.y, _receipt) # 与原生一次命中的血池顺序一致。
	var struck: Variant = _receipt.get("recipient") # 盾卫代伤时取得实际收据。
	if is_instance_valid(struck):
		_apply_status(struck)
	return casualty

## 真实承伤的 [param target] 决定折射和状态。流光仅在每弹首次接触该目标时刷新演出与词条。
func _apply_status(target: Character000Base) -> void:
	if target.is_hypno or (target is Zombie000Base and target.retiring_from_battle):
		return
	if _flow:
		var id: int = target.get_instance_id() # 与索敌共用命中 ID，不保留角色引用。
		if _promotion_hit_ids.has(id):
			return
		_promotion_hit_ids[id] = true
	if max_attack_num == -1:
		_runtime.flash_hit(global_position, _tint)
	if (_traits & Trait.REFRACT) != 0 and target is Zombie000Base:
		_runtime.mark_refraction(target, _shot, _traits)
	if target.is_death or target.is_queued_for_deletion():
		return
	match kind:
		Kind.GOLD:
			if _traits & Trait.PIERCE:
				AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.DEGRADATION, _shot.source_id, 0.3)
		Kind.VIOLET:
			if target is Zombie000Base and AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.STUN, _shot.source_id, 0.2):
				target.apply_projectile_knockback(_shot.cell_pitch.x * 0.16)
		Kind.BLUE:
			AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.FREEZE_CHARGE, _shot.source_id, 2.0)
		Kind.RED:
			AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.DETONATION_CHARGE, _shot.source_id, 1.0, 0.0, _detonation)

## 返回 [param outer] 与 [param inner] 半径交替的共享五角星。
static func _star_points(outer: float, inner: float) -> PackedVector2Array:
	var points := PackedVector2Array() # 几何仅在脚本初始化时计算一次。
	for vertex: int in range(10): # 外尖与凹角交替。
		points.append(Vector2.UP.rotated(TAU * float(vertex) / 10.0) * (outer if vertex % 2 == 0 else inner))
	return points

## 在原生弹身画布上绘制清晰的镶边和高光切面。
func _draw_face() -> void:
	_face_sprite.draw_circle(Vector2.ZERO, 15.0, Color(_tint, 0.16), true, -1, true)
	_face_sprite.draw_colored_polygon(_edge, Color(0.13, 0.08, 0.22, 0.97))
	_face_sprite.draw_colored_polygon(_face, _tint)
	_face_sprite.draw_colored_polygon(_facet, _tint.lerp(Color.WHITE, 0.71))

## 沿真实飞行方向绘制流光带和各星的分色尾迹。
func _draw_trail() -> void:
	var length: float = _trail_length() # 蓝色彗星和流光有更长的轮廓。
	body.draw_line(Vector2(-length, 0), Vector2(-5, 0), Color(_tint, 0.24), 7.0 if _flow else 4.0, true)
	body.draw_line(Vector2(-length * 0.66, 0), Vector2(-4, 0), Color(_tint, 0.86), 2.5, true)
	if _flow or kind == Kind.BLUE:
		body.draw_line(Vector2(-length * 0.78, -4), Vector2(-12, -2), Color(_tint, 0.62), 1.5, true)
		body.draw_line(Vector2(-length * 0.85, 4), Vector2(-16, 2), Color(_tint, 0.38), 1.2, true)

## 返回飞行及退场所用的初始尾迹长度，原生星只在消散时带一小段余光。
func _trail_length() -> float:
	return 52.0 if _flow else (36.0 if kind == Kind.BLUE else (15.0 if _native_exit else 24.0))
