## 寒冰弹保留原生命中；转职时在同一伤害事务追加规则与派生效果。
extends BulletLinear000Base
class_name Bullet002PeaSnow

## 命中后的减速持续秒数；二类防具仍可阻挡寒冷。
@export var time_be_decelerated: float = 3.0
## 本次原生发射参数完成冻结时发送一次；额外发射不发送。
signal native_parameters_frozen(shot: SnowPeaShot)
## 已冻结的寒冰转职发射；普通原版豌豆为空。
var promotion_shot: SnowPeaShot
## 冰雕释放的跨行穿透弹，不新登记冰雕来源；此前已登记的目标死亡仍可形成冰雕。
var is_prism: bool = false
## 实际扣血回执；只记录当前普通僵尸命中。
var _receipt: Dictionary = {}
## 每颗弹只记录首个有效普通僵尸，供酷刑留下冰痕。
var _trail_started: bool = false
## 棱锥在真正承伤者处也去重，防止重复打中代伤保护者。
var _prism_scope: SnowPeaStatueHit
## 真实承伤者在本击扣血前的寒冷快照，代伤不能沿用原接触者的脆性资格。
var _impact_was_slowed: bool = false
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
		_prism_scope = SnowPeaStatueHit.new(promotion_shot, 0)
	if promotion_shot.loadout.has(&"deep_cold"):
		body.modulate = Color(0.56, 0.76, 1.0)

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

## 回廊和棱锥中途命中特效独立复制，避免首次命中移走后续碰撞所需的效果节点。
func _copies_continuing_hit_effect() -> bool:
	return is_prism or (promotion_shot != null and promotion_shot.loadout.has(&"corridor"))

## 普通与转职寒冰共用真实承伤回执，减速随代伤结果结算；派生伤害仍只读取真实扣血。
func _impact_receipt() -> Variant:
	return _receipt

## [param enemy] 为原生资格已确认的命中目标或落空；普通与转职弹共用负面状态免疫入口。
func _attack_enemy(enemy: Character000Base) -> void:
	_receipt.clear()
	if promotion_shot == null:
		super(enemy)
		var native_recipient: Variant = _receipt.get("recipient") # 未带技能书的普通寒冰也按实际保护者施加减速。
		if is_instance_valid(native_recipient) and native_recipient is Zombie000Base \
				and _can_attack_character(native_recipient, false) and native_recipient.hp_component.curr_hp_armor2 <= 0:
			AdventurePlantNegativeEffects.apply(native_recipient, AdventurePlantNegativeEffects.Kind.ICE_SLOW,
				0, time_be_decelerated)
		return
	var position_at_hit: Vector2 = global_position # 扣血后原目标可能已死亡或移位。
	var target_lane: int = enemy.lane if enemy is Zombie000Base else lane # 溅射以实际接触的行确定格距。
	super(enemy)
	var dealt_damage: bool = int(_receipt.get("actual_loss", 0)) > 0 # 格挡或伤害免疫只阻止伤害派生效果，不吞掉有效命中的寒冷。
	var recipient: Variant = _receipt.get("recipient") # 寒冷随真实承伤者结算，五阶铁桶代伤不能吞掉控制。
	if is_instance_valid(recipient) and recipient is Zombie000Base:
		if not bool(_receipt.get("duplicate_hit", false)) and _can_attack_character(recipient, false):
			if dealt_damage and not _trail_started and promotion_shot.loadout.has(&"torment"):
				_trail_started = true
				if not recipient.is_hypno:
					SnowPeaIceTrail.track.call_deferred(recipient, promotion_shot)
			SnowPeaImpact.apply_direct_status(recipient, promotion_shot, _impact_was_slowed, is_prism, curr_attack_num)
		elif dealt_damage and not _trail_started and promotion_shot.loadout.has(&"torment"):
			# 首个有效承伤者已死亡或不能继续受击，后续穿透不能重新登记路径起点。
			_trail_started = true
	if dealt_damage and is_instance_valid(enemy):
		SnowPeaImpact.queue_splash(enemy, position_at_hit, target_lane, last_impact_damage,
			promotion_shot, 0 if is_prism else curr_attack_num)

## [param zombie]、[param mode]、[param armor] 与 [param bonus] 沿用原生结算参数。
## 返回最终实际死者；状态快照和斯卡蒂登记均在最终承伤者的第一次扣血前完成。
func _apply_zombie_impact(zombie: Zombie000Base, mode: BulletRegistry.AttackMode,
		armor: float, bonus: Vector2i) -> Zombie000Base:
	if promotion_shot == null:
		return (zombie.hp_component as HpComponentZombie).apply_hit(
			attack_value, mode, true, trigger_be_attack_sfx, true, armor, bonus.x, bonus.y, _receipt)
	var scope: SnowPeaStatueHit = _prism_scope if is_prism else SnowPeaStatueHit.new(promotion_shot, curr_attack_num) # 冰锥跨接触去重，根弹逐击保存寒冷状态。
	var casualty: Zombie000Base = (zombie.hp_component as HpComponentZombie).apply_hit(
		attack_value, mode, true, trigger_be_attack_sfx, true, armor, bonus.x, bonus.y, _receipt, scope)
	_impact_was_slowed = scope.was_slowed
	return casualty
