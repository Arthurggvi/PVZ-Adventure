@abstract
extends ComponentNormBase
## 基础攻击组件，攻击组件都有攻击射线检测组件（detect_component）
## 列外:全局攻击组件同时使用全局检测组件
class_name AttackComponentBase

@onready var detect_component: DetectComponent = $DetectComponent

### 是否正在攻击
#var is_attack := false
## 影响是否可以攻击的因素
enum E_IsAttackFactors{
	Enbale,			## 组件是否禁用
	RayEnemy,		## 射线检测到敌人
	Anim,			## 动画是否可以攻击(仙人掌动画切换\气球在空中\扶梯僵尸搭梯子动画)
	Character,		## 特殊角色本身(使用该因素不能有冲突)
}
## 默认攻击射线检测敌人为false
var is_attack_factors:Dictionary[E_IsAttackFactors, bool] = {
	E_IsAttackFactors.RayEnemy:false,
}
## 是否可以攻击的结果
var is_attack_res := false
## 持续范围攻击可跳过目标因素，仍保留组件、动画与角色自身禁用条件。
var _requires_target: bool = true

## [param value] 更新 [param factor] 对攻击的许可；所有有效因素都通过才可攻击。
func update_is_attack_factors(value:bool, factor:E_IsAttackFactors):
	is_attack_factors[factor] = value
	_refresh_attack_state()

## [param required] 为假时只忽略无目标，不绕过睡眠、禁用、动画和角色条件。
func set_requires_target(required: bool) -> void:
	_requires_target = required
	_refresh_attack_state()

## 统一合成真实组件状态，离树后不能因恢复配置而重新启动攻击时钟。
func _refresh_attack_state() -> void:
	is_attack_res = is_enabling and is_inside_tree()
	for factor: E_IsAttackFactors in is_attack_factors: # 只允许持续模式排除原生目标因素。
		if factor != E_IsAttackFactors.RayEnemy or _requires_target:
			is_attack_res = is_attack_res and is_attack_factors[factor]
	if is_attack_res:
		attack_start()
	else:
		attack_end()

signal signal_change_is_attack(value:bool)

func _ready() -> void:
	super()
	detect_component_init()

func detect_component_init():
	if is_instance_valid(detect_component):
		detect_component.signal_can_attack.connect(update_is_attack_factors.bind(true, E_IsAttackFactors.RayEnemy))
		detect_component.signal_not_can_attack.connect(update_is_attack_factors.bind(false, E_IsAttackFactors.RayEnemy))


## 启用组件
func enable_component(is_enable_factor:E_IsEnableFactor):
	super(is_enable_factor)
	if is_instance_valid(detect_component):
		detect_component.enable_component(is_enable_factor)
	update_is_attack_factors(is_enabling, E_IsAttackFactors.Enbale)

## 禁用组件
func disable_component(is_enable_factor:E_IsEnableFactor):
	super(is_enable_factor)
	#print(owner.name)
	if is_instance_valid(detect_component):
		detect_component.disable_component(is_enable_factor)
	update_is_attack_factors(false, E_IsAttackFactors.Enbale)

## 开始攻击
func attack_start():
	#print("开始攻击")
	signal_change_is_attack.emit(true)

## 结束攻击
func attack_end():
	signal_change_is_attack.emit(false)

## 被魅惑
func owner_be_hypno():
	detect_component.owner_be_hypno()

@abstract
func owner_update_speed(speed_product:float)
