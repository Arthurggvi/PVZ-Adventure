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
## 间隔帧数
var frame_counter := 0
## Landed hit event, not merely target acquisition. Allows debuffs to be gated by bite.
signal bite_landed(target: Node, amount: int)


func _ready() -> void:
	super()
	curr_attack_value_per_min = init_attack_value_per_min

## 修改攻击速度,通过修改攻击值实现
func owner_update_speed(speed_product:float):
	#print("攻击组件修改攻击速度")
	update_attack_value(speed_product, E_AttackValueFactor.Speed)

## 修改攻击值
func update_attack_value(value:float, influence_factor:E_AttackValueFactor):
	attack_value_factor[influence_factor] = value
	var res_product = GlobalUtils.get_dic_product(attack_value_factor)
	curr_attack_value_per_min = int(init_attack_value_per_min * res_product)

func _physics_process(delta: float) -> void:
	if is_enabling and is_attack_res and not owner.is_stunned():
		frame_counter = wrapi(frame_counter + 1, 0, 8)
		if not is_instance_valid(detect_component.enemy_can_be_attacked):
			return
		if frame_counter==0 and is_instance_valid(detect_component.enemy_can_be_attacked):
			# 保留本次命中的目标，扣血触发死亡时检测组件可能会切换目标。
			var target: Character000Base = detect_component.enemy_can_be_attacked
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
	target.be_zombie_eat(damage, owner)
	if was_living_plant and is_instance_valid(target) and target.is_death:
		SoundManager.play_sfx_with_pool(PLANT_EATEN_SFX)


## 攻击一次发亮，动画调用
func attack_once():
	if owner.is_stunned():
		return
	if is_instance_valid(detect_component.enemy_can_be_attacked) and not owner.is_death:
		detect_component.enemy_can_be_attacked.be_zombie_eat_once(owner)
		SoundManager.play_character_SFX("Chomp")
	elif is_instance_valid(detect_component.brain):
		#detect_component = detect_component as DetectComponentZombie
		detect_component.brain.be_attack_once(25)
		SoundManager.play_character_SFX("Chomp")



