## 石像只消耗固定石壳；复用普通伤害路由，归零后等待换体，不进入普通僵尸死亡流程。
extends HpComponentZombie
class_name HpComponentStoneStatue

## 所有等阶共用的石壳生命，不受封存普僵的等阶或迷你倍率影响。
const SHELL_HEALTH: int = 3000
## 石壳首次耗尽后通知控制器；同一帧重复攻击不能重复请求换体。
signal shell_broken
## 入树前已由普通等阶绑定计算的普僵生命，只用于原波次的封存生命预算。
var contained_body_hp: int = 0
## 破壳后拒绝后续命中与治疗，直至帧末换体完成。
var _break_requested: bool = false
## 清场、碾压或抓取使用真正死亡通道，不释放新的普僵。
var _cleanup_requested: bool = false

## 保存继承场景中的真实普僵生命，再初始化独立石壳及其血条。
func _ready() -> void:
	contained_body_hp = max_hp
	max_hp = SHELL_HEALTH
	max_hp_armor1 = 0
	max_hp_armor2 = 0
	death_hp = -1
	super()

## [param amount] 为即将扣除的伤害；石壳归零属于换体，不能触发致死前的冰雕或亡语观察。
func would_die_from_damage(amount: int) -> bool:
	return _cleanup_requested and super.would_die_from_damage(amount)

## [param attack_value]、[param bullet_mode] 和表现开关沿用普通受击；同击附伤与回执也交给原路由。
## [param is_drop_on_death]、[param trigger_be_attack_SFX]、[param is_drop_2] 沿用原路由的掉落与音效选项。
## [param armor_multiplier]、[param bonus_damage]、[param bonus_cap] 保留原防具及附伤规则。
## [param receipt] 回报旧石壳的损失；[param hit_scope] 保留同一攻击的承伤去重。
## [param _pre_resolved_damage] 供签名兼容，石壳始终由原路由重新结算。
## 破壳排队后只返回空伤害，不把余伤传给尚未生成的普僵。
func apply_hit(attack_value: int, bullet_mode: BulletRegistry.AttackMode,
		is_drop_on_death: bool, trigger_be_attack_SFX: bool, is_drop_2: bool = true,
		armor_multiplier: float = 1.0, bonus_damage: int = 0, bonus_cap: int = -1,
		receipt: Variant = null, hit_scope: CombatHitScope = null, _pre_resolved_damage: int = -1) -> Zombie000Base:
	if _break_requested and not _cleanup_requested:
		reset_hit_receipt(receipt, owner_character)
		return null
	return super.apply_hit(attack_value, bullet_mode, is_drop_on_death, trigger_be_attack_SFX,
		is_drop_2, armor_multiplier, bonus_damage, bonus_cap, receipt, hit_scope)

## [param amount] 消耗石壳，最大只扣当前剩余生命；[param cause] 仅在真正清理时用于死亡记录。
func apply_body_loss(amount: int, cause: CombatHitScope.DeathCause = CombatHitScope.DeathCause.NORMAL) -> void:
	if _cleanup_requested:
		super.apply_body_loss(amount, cause)
		return
	if _break_requested or amount <= 0:
		return
	super.apply_body_loss(mini(amount, curr_hp), cause)
	if curr_hp == 0:
		_break_requested = true
		shell_broken.emit()

## [param is_drop] 沿用清理者的残肢开关；强制清理恢复原死亡阈值，并取消已排队的破壳。
func Hp_loss_death(is_drop: bool = true) -> void:
	_cleanup_requested = true
	death_hp = 0
	super.Hp_loss_death(is_drop)
	if not is_death:
		apply_body_loss(curr_hp) # 已破壳的零生命也必须发出一次真正死亡通知。

## [param amount] 为治疗量；石壳已经破碎时不接受同一帧回调中的复活式治疗。
func heal(amount: int) -> int:
	return 0 if _break_requested or _cleanup_requested else super.heal(amount)

## 返回石壳本身的存活比例，避免特殊负死亡阈值改变百分比处决边界。
func living_health_fraction() -> float:
	return clampf(float(curr_hp) / float(SHELL_HEALTH), 0.0, 1.0)

## 迷你模式只缩小封存普僵的实际生命；石壳仍固定承受 3000 点。
func update_mini_zombie_hp() -> void:
	contained_body_hp = floori(float(contained_body_hp) * 0.5)

## 返回此刻是否仍允许执行破壳换体；真正死亡或清理优先于已排队的视觉效果。
func can_release_zombie() -> bool:
	return _break_requested and not _cleanup_requested and not is_death
