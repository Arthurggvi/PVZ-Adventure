extends AttackComponentBase
class_name AttackComponentZombieNorm
## 普通僵尸攻击组件

## 僵尸完成最后一口啃食时播放的原版吞咽音效。
const PLANT_EATEN_SFX := preload("res://assets/audio/sounds/gulp.ogg")

@export_group("每秒伤害值")
@export var init_attack_value_per_min :int = 100

## 每分钟攻击值
var curr_attack_value_per_min :int = 100
enum E_AttackValueFactor{
	Death,			## 死亡，攻击力置为0
	Speed,			## 攻击速度，
	PaperDrop,		## 报纸掉落，攻击力翻倍
	JacksonEnter,	## 舞王入场时,攻击值为0
	AdventureBiteBoost, ## Temporary tier flag bite bonus
	AdventureSpeciesBite, ## Permanent / accumulating species traits
	AdventureSpeciesRage, ## Paper-loss multiplier independent of normal bite
}

var attack_value_factor:Dictionary[E_AttackValueFactor, float] = {}
## 距离下一口累计的动作帧；变速保留已推进的小数进度。
var frame_counter := 0.0
## Landed hit event, not merely target acquisition. Allows debuffs to be gated by bite.
signal bite_landed(target: Node, amount: int)


func _ready() -> void:
	super()
	curr_attack_value_per_min = init_attack_value_per_min

## 接收角色速度变更信号。[param speed_product] 也可能来自舞团的共享速度。
func owner_update_speed(speed_product: float) -> void:
	# 独立行动倍率已作用于间隔，只让其他原生速度来源改变每口伤害。
	var action_speed: float = owner.action_rate() # 暂停期间没有出手，恢复时将重新合成每口伤害。
	if action_speed > 0.0:
		update_attack_value(speed_product / action_speed, E_AttackValueFactor.Speed)


## 推进一次物理帧的啃咬进度；到达出手间隔时返回 true 并保留余量。
func _advance_bite_interval() -> bool:
	frame_counter += owner.action_rate()
	if frame_counter < 8.0:
		return false
	frame_counter -= 8.0
	return true

## [param factor] 仅提高等阶基础啃食值，现有独立伤害因子保持原值。
func scale_base_attack(factor: float) -> void:
	restore_base_attack(roundi(init_attack_value_per_min * factor))

## [param amount] 是已经结算好的出场攻击基数；复制时保留本实例的速度与攻击增益因子。
func restore_base_attack(amount: int) -> void:
	init_attack_value_per_min = maxi(0, amount)
	curr_attack_value_per_min = int(init_attack_value_per_min * GlobalUtils.get_dic_product(attack_value_factor))

## 修改攻击值
func update_attack_value(value:float, influence_factor:E_AttackValueFactor):
	attack_value_factor[influence_factor] = value
	var res_product = GlobalUtils.get_dic_product(attack_value_factor)
	curr_attack_value_per_min = int(init_attack_value_per_min * res_product)

func _physics_process(delta: float) -> void:
	if is_enabling and is_attack_res and not owner.is_action_suspended():
		if _advance_bite_interval() and is_instance_valid(detect_component.enemy_can_be_attacked):
			# 保留本次命中的目标，扣血触发死亡时检测组件可能会切换目标。
			var target: Character000Base = detect_component.enemy_can_be_attacked
			if target is Plant000Base and target.battle_hidden_from_zombies:
				return
			# 计算这 8 帧累计的啃食伤害，并应用攻击者当前的伤害修正。
			var damage: int = owner.hp_component.outgoing_damage(
				int(curr_attack_value_per_min * delta * 8))
			_apply_bite(target, damage)
			if damage > 0 and is_instance_valid(target):
				bite_landed.emit(target, damage)


## 施加一次啃食伤害，植物首次被啃死时播放吞咽音效。
## [param target] 检测组件确认有效的本次受击目标。
## [param damage] 交给目标生命组件结算的啃食伤害。
func _apply_bite(target: Character000Base, damage: int) -> void:
	# 记录扣血前的状态，避免对已经死亡的植物重复播放。
	var was_living_plant := target is Plant000Base and not target.is_death
	var contact: Vector2 = target.hurt_box_component.global_position if is_instance_valid(target.hurt_box_component) else target.global_position # 伤害可销毁植株，先采样。
	target.be_zombie_eat(damage, owner)
	if was_living_plant and is_instance_valid(target) and target.is_death:
		SoundManager.play_world_sfx(PLANT_EATEN_SFX, self, contact, 0.0, 1.0, &"bite_finish")


## 攻击一次发亮，动画调用
func attack_once():
	if owner.is_action_suspended():
		return
	if is_instance_valid(detect_component.enemy_can_be_attacked) and not owner.is_death:
		var target: Character000Base = detect_component.enemy_can_be_attacked # 动画释放当帧的接触对象。
		if target is Plant000Base and target.battle_hidden_from_zombies:
			return
		var contact: Vector2 = target.hurt_box_component.global_position if is_instance_valid(target.hurt_box_component) else target.global_position # 取活动甲板上的触点。
		target.be_zombie_eat_once(owner)
		SoundManager.play_character_SFX(&"Chomp", self, contact)
	elif is_instance_valid(detect_component.brain):
		#detect_component = detect_component as DetectComponentZombie
		var contact: Vector2 = detect_component.brain.global_position # 脑子在地图上的世界锚点。
		detect_component.brain.be_attack_once(25)
		SoundManager.play_character_SFX(&"Chomp", self, contact)
