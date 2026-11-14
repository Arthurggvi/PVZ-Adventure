## 寒冰弹保留原生命中；转职时在同一伤害事务追加规则与派生效果。
extends BulletLinear000Base
class_name Bullet002PeaSnow

## 命中后的减速持续秒数；二类防具仍可阻挡寒冷。
@export var time_be_decelerated: float = 3.0
## 本次原生发射参数完成冻结时发送一次；额外发射不发送。
signal native_parameters_frozen(shot: SnowPeaShot)
## 已冻结的寒冰转职发射；普通原版豌豆为空。
var promotion_shot: SnowPeaShot
## 冰雕释放的跨行穿透弹，禁止再次形成冰雕。
var is_prism: bool = false
## 实际扣血回执；只记录当前普通僵尸命中。
var _receipt: Dictionary = {}
## 每颗弹只记录首个有效普通僵尸，供酷刑留下冰痕。
var _trail_started: bool = false
## 棱锥在真正承伤者处也去重，防止重复打中代伤保护者。
var _prism_scope: CombatHitScope
## 棱锥剩余战斗秒数，限制离盘弹体与碰撞寿命。
var _prism_lifetime: float = 1.5

## [param bullet_paras] 来自原攻击组件；根弹从同一入口冻结合格状态和伤害。
func init_bullet(bullet_paras: Dictionary) -> void:
	super(bullet_paras)
	if promotion_shot != null and promotion_shot.freeze_native_parameters(bullet_paras):
		native_parameters_frozen.emit(promotion_shot)

## 初始化原生飞行；转职弹保留低温特性，火炬只能转换普通原版弹。
func _ready() -> void:
	super()
	if promotion_shot == null:
		return
	is_can_up = false
	if is_prism or promotion_shot.loadout.has(&"corridor"):
		max_attack_num = -1
		unique_target_hits = true
	if is_prism:
		_prism_scope = CombatHitScope.new()
	if promotion_shot.loadout.has(&"deep_cold"):
		body.modulate = Color(0.25, 0.46, 1.0)

## [param delta] 为实战秒；棱锥保留原生射程门禁并额外限制寿命。
func _physics_process(delta: float) -> void:
	if is_prism:
		_prism_lifetime -= delta
		if _prism_lifetime <= 0.0:
			queue_free()
			return
	super(delta)

## [param enemy] 为本次接触目标；回廊只查看本击结算前已有的寒冷。
func _continues_after_hit(enemy: Character000Base) -> bool:
	if is_prism:
		return true
	if promotion_shot != null and promotion_shot.loadout.has(&"corridor"):
		return enemy is Zombie000Base and not enemy.is_hypno and enemy.is_cold_slowed()
	return super(enemy)

## 回廊中途命中特效需要复制；棱锥的轻量场景不带粒子。
func _copies_continuing_hit_effect() -> bool:
	return promotion_shot != null and promotion_shot.loadout.has(&"corridor")

## 转职命中只在真实承伤后传递词条，普通弹无回执。
func _impact_receipt() -> Variant:
	return _receipt if promotion_shot != null else null

## [param enemy] 为原生资格已确认的命中目标或落空。
func _attack_enemy(enemy: Character000Base) -> void:
	if promotion_shot == null:
		super(enemy)
		if enemy is Zombie000Base and _can_attack_character(enemy) and enemy.hp_component.curr_hp_armor2 <= 0:
			enemy.be_ice_decelerate(time_be_decelerated)
		return
	var was_slowed: bool = enemy is Zombie000Base and enemy.is_cold_slowed() # 脆性只看命中前寒冷。
	var position_at_hit: Vector2 = global_position # 扣血后原目标可能已死亡或移位。
	var target_lane: int = enemy.lane if enemy is Zombie000Base else lane # 溅射以实际接触的行确定格距。
	_receipt.clear()
	super(enemy)
	if int(_receipt.get("actual_loss", 0)) <= 0:
		return
	if is_instance_valid(enemy) and enemy is Zombie000Base:
		if _receipt.get("recipient") == enemy and _can_attack_character(enemy):
			if not _trail_started and promotion_shot.loadout.has(&"torment"):
				_trail_started = true
				if not enemy.is_hypno:
					SnowPeaIceTrail.track.call_deferred(enemy, promotion_shot)
			SnowPeaImpact.apply_direct_status(enemy, promotion_shot, was_slowed, is_prism, curr_attack_num)
		elif not _trail_started and promotion_shot.loadout.has(&"torment"):
			# 首个有效接触已经致死或由保护者代伤，后续穿透也不能重复登记路径起点。
			_trail_started = true
	if is_instance_valid(enemy):
		SnowPeaImpact.queue_splash(enemy, position_at_hit, target_lane, last_impact_damage,
			promotion_shot, 0 if is_prism else curr_attack_num)

## [param zombie]、[param mode]、[param armor] 与 [param bonus] 沿用原生结算参数。
## 返回最终实际死者；斯卡蒂只观察本击本体跨越真实阈值的瞬间。
func _apply_zombie_impact(zombie: Zombie000Base, mode: BulletRegistry.AttackMode,
		armor: float, bonus: Vector2i) -> Zombie000Base:
	if promotion_shot == null:
		return super(zombie, mode, armor, bonus)
	var scope: CombatHitScope = _prism_scope # 根弹通常不需要承伤去重组，仅斯卡蒂添加本击观察。
	if not is_prism and promotion_shot.loadout.has(&"skadi"):
		scope = SnowPeaStatueHit.new(promotion_shot, curr_attack_num)
	return (zombie.hp_component as HpComponentZombie).apply_hit(
		attack_value, mode, true, trigger_be_attack_sfx, true, armor, bonus.x, bonus.y, _receipt, scope)
