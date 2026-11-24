## 西瓜沿用原生弧线及碰撞；只有转职弹扩展溅射、命中控制与幻影。
extends Bullet000ParabolaBase
class_name Bullet012Melon

## 克拉托斯复用一份瓜体和光弧绘制逻辑。
const Phantom = preload("res://scripts/adventure/research/melon_phantom_visual.gd")
## 幻影只记最近七个物理位置，在发射之间不分配尾迹节点。
const TRAIL_SIZE: int = 7
## 脱线一击沿原受击方向推开约五分之一格。
const KNOCKBACK_DISTANCE: float = 20.0
## 震撼每次加一秒，剩余时间上限三秒，其他来源的更长眩晕仍保留。
const STUN_LIMIT: float = 3.0
## 限制同一物理步创建的转职瓜飞溅特效；多发照常结算。
const IMPACT_LIMIT: int = 8
## 由本战场弹体容器记录特效帧号与当帧次数。
const IMPACT_BUDGET: StringName = &"_melon_promotion_impact_budget"

## 原生命中区域继续负责碰撞分层和跨行范围。
@onready var spatter_component: SpatterComponent = $SpatterComponent
## 转职弹启用共享的结算范围和视觉配额。
var _promoted: bool = false
## 爆碎使每个溅射目标获得完整的本发基础伤害。
var _full_splash: bool = false
## 命中推动普通可控制僵尸。
var _knockback: bool = false
## 命中延长普通僵尸的现有眩晕。
var _stun: bool = false
## 克拉托斯才维护各弹的三道残影。
var _phantom: bool = false
## 重磅向固定地格发射的次弹，下降时才开始查询地面受击框。
var _landing_only: bool = false
## 初始化后已乘卡片和转职倍率的弹体值，避免继承直击目标专属修正。
var _scaled_damage: int
## 一颗瓜对同一个真实承伤者只生效一次，包括代伤者。
var _hit_scope: CombatHitScope
## 幻影环形历史中最新的采样索引。
var _trail_cursor: int = 0
## 固定容量的幻影世界轨迹；普通瓜不会分配位置。
var _trail := PackedVector2Array()

## 发出前冻结转职：[param full_splash]、[param knockback]、[param stun] 和 [param phantom]。
## [param landing_only] 为真时这是瞄准真实地格的重磅次弹，仍由原生受击框在落地段结算。
func configure_promotion(full_splash: bool, knockback: bool, stun: bool, phantom: bool, landing_only: bool = false) -> void:
	_promoted = true
	_full_splash = full_splash
	_knockback = knockback
	_stun = stun
	_phantom = phantom
	_landing_only = landing_only
	_hit_scope = CombatHitScope.new()
	is_rotate = false # 已有物理步顺手更新瓜体旋转，密集投掷不再为每枚瓜开循环 Tween。
	if _landing_only:
		$Area2DAttack.monitoring = false
		$SpatterComponent/Area2DSpatter.monitoring = false

## [param bullet_paras] 由原生弹初始化并缩放伤害；这里缓存溅射基础。
func init_bullet(bullet_paras: Dictionary[E_InitParasAttr, Variant]) -> void:
	super(bullet_paras)
	_scaled_damage = attack_value

## 幻影从弹口出生，样本尚未拉开前都重叠在发射坐标。
func _ready() -> void:
	if _phantom and lane <= 1:
		movement_component.parabola_height = -175.0 # 上边路收低弧顶，让真实弹体和紫色残影都留在画面内。
	super()
	if _phantom:
		$Body/BulletBody.material = Phantom.core_material()
		bullet_effect.modulate = Color(1.13, 0.86, 1.35)
		_trail.resize(TRAIL_SIZE)
		_trail.fill(global_position)

## [param delta] 保留原生抛射和影子。只有幻影刷新定长残影缓冲。
func _physics_process(delta: float) -> void:
	if _promoted:
		body.rotation = fposmod(body.rotation + delta * TAU, TAU)
	if _landing_only and movement_component.curr_time + delta >= movement_component.all_time * 0.62:
		_landing_only = false
		area_2d_attack.monitoring = true
		spatter_component.area_2d_spatter.monitoring = true
	if _promoted and is_instance_valid(target_enemy):
		if not _can_attack_character(target_enemy, false) or target_enemy.is_hypno:
			target_enemy = null
		elif target_enemy.lane >= 0 and target_enemy.lane != lane and is_instance_valid(Global.main_game):
			var manager: ZombieManager = Global.main_game.zombie_manager # 合行或动态地形退场时先核对新攻击线。
			if manager.is_lane_open(target_enemy.lane):
				lane = target_enemy.lane
				global_pos_y_shadow = manager.all_zombie_rows[lane].zombie_create_position.global_position.y
				z_index = lane * 50 + 45
	super(delta)
	if _phantom and not is_queued_for_deletion():
		_trail_cursor = (_trail_cursor + 1) % TRAIL_SIZE
		_trail[_trail_cursor] = global_position
		queue_redraw()

## 棋盘整体偏移 [param displacement] 时让残影与原生弹体同时移动。
func translate_with_board(displacement: Vector2) -> void:
	super(displacement)
	for index: int in range(_trail.size()): # 定长历史与当前弹道使用相同世界坐标。
		_trail[index] += displacement

## 所有残影直接画在现有弹体画布上。
func _draw() -> void:
	if not _phantom or _trail.is_empty():
		return
	var close: Vector2 = to_local(_trail[posmod(_trail_cursor - 2, TRAIL_SIZE)]) # 向前两帧的紧邻重影。
	var middle: Vector2 = to_local(_trail[posmod(_trail_cursor - 4, TRAIL_SIZE)]) # 四帧形成第二层。
	var far: Vector2 = to_local(_trail[posmod(_trail_cursor - 6, TRAIL_SIZE)]) # 最远影六帧后自然退出。
	if close.length_squared() > 0.25:
		Phantom.draw_flight(self, close, middle, far, (-close).angle())

## [param enemy] 可为空；先走正常直击，再在同一原生碰撞区域查询溅射对象。
func _attack_enemy(enemy: Character000Base) -> void:
	super(enemy)
	spatter_component.spatter_all_area_zombie(enemy if is_instance_valid(enemy) else null, lane, _resolve_splash if _promoted else Callable())

## 把 [param zombie] 的直击交给原生命路由，保留 [param mode]、[param armor] 和 [param bonus]。
## 转职弹额外在真实承伤者上去重并施加命中控制。
func _apply_zombie_impact(zombie: Zombie000Base, mode: BulletRegistry.AttackMode,
		armor: float, bonus: Vector2i) -> Zombie000Base:
	if not _promoted:
		return super(zombie, mode, armor, bonus)
	return _hit_promoted_zombie(zombie, attack_value, mode, armor, bonus, trigger_be_attack_sfx)

## [param enemy] 已通过原生溅射几何筛选；[param native_damage] 为普通西瓜的分摊值。
func _resolve_splash(enemy: Character000Base, native_damage: int) -> void:
	if enemy.is_hypno or not is_attack_active():
		return
	var damage: int = _scaled_damage if _full_splash else native_damage # 普通路线继续分摊；爆碎逐个拿完整基础值。
	if _full_splash and attack_context != null:
		damage = attack_context.modify_damage(damage, enemy)
	if enemy is Zombie000Base:
		var armor: float = attack_context.armor_multiplier if attack_context != null else 1.0 # 溅射走已有的防具和代伤门面。
		var casualty: Zombie000Base = _hit_promoted_zombie(enemy, damage, BulletRegistry.AttackMode.Penetration,
			armor, Vector2i(0, -1), false) # 每个溅射对象使用同一颗瓜的命中资格。
		if attack_context != null:
			attack_context.resolve_kill(casualty)
	else:
		enemy.be_attacked_bullet(damage, BulletRegistry.AttackMode.Penetration, true, false, 0, -1, null, _hit_scope)
		if attack_context != null and is_instance_valid(enemy) and enemy is ZB000Base and enemy.is_death:
			attack_context.resolve_kill(enemy)

## 对 [param zombie] 结算 [param damage] 和既有 [param mode]、[param armor]、[param bonus]。
## [param play_sfx] 只在直接命中时沿用原生受击声；普通伤害无状态时不申请回执。
func _hit_promoted_zombie(zombie: Zombie000Base, damage: int, mode: BulletRegistry.AttackMode,
		armor: float, bonus: Vector2i, play_sfx: bool) -> Zombie000Base:
	var receipt: Variant = {} if _knockback or _stun else null # 仅控制词条需要读取代伤后的实体。
	var casualty: Zombie000Base = (zombie.hp_component as HpComponentZombie).apply_hit(
		damage, mode, true, play_sfx, true, armor, bonus.x, bonus.y, receipt, _hit_scope) # 防具与代伤由生命路由决定。
	if receipt is Dictionary and not receipt.get("duplicate_hit", false):
		var recipient: Variant = receipt.get("recipient", zombie) # 敌人可能在扣血时被移除。
		if is_instance_valid(recipient) and recipient is Zombie000Base and not recipient.is_death \
				and not recipient.is_hypno and recipient.can_receive_control_effects():
			_apply_control(recipient)
	return casualty

## 仅给实际接触且允许受控的 [param target] 施加本发词条。
func _apply_control(target: Zombie000Base) -> void:
	if _knockback:
		target.apply_projectile_knockback(KNOCKBACK_DISTANCE)
	if _stun:
		var timer: Timer = target.all_timer[Character000Base.E_TimerType.Stun] # 读原生剩余时间，不建立第二份眩晕。
		var remaining: float = timer.time_left if is_instance_valid(timer) else 0.0 # 已过期时从零起算。
		if remaining < STUN_LIMIT:
			target.be_stunned(minf(STUN_LIMIT, remaining + 1.0))

## [param enemy] 可为空，仍需为落地表现占用一份预算。
func _should_show_impact(enemy: Character000Base) -> bool:
	if not _promoted:
		return super(enemy)
	var host: Node = get_parent() # 只在同一局内共用计数。
	var frame: int = Engine.get_physics_frames() # 一步内大量同时命中的尾部顺手合并视觉。
	var quota: Vector2i = host.get_meta(IMPACT_BUDGET, Vector2i(-1, 0)) # 只保存两项整数，不保留节点。
	if quota.x != frame:
		quota = Vector2i(frame, 0)
	if quota.y >= IMPACT_LIMIT:
		return false
	quota.y += 1
	host.set_meta(IMPACT_BUDGET, quota)
	return true
