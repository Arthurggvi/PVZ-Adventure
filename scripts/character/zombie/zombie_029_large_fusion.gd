## 大型融合僵尸：根节点只声明能力并协调翻滚、分裂与通用死亡生命周期。
extends Zombie000Base
class_name Zombie029LargeFusion

## 有限次碾压与原生后抛的唯一状态拥有者。
@onready var rolling_attack: AttackComponentZombieLargeFusion = $AttackComponent
## 本体损血和邻行死亡召唤的独立计数器。
@onready var brood: LargeFusionBrood = $FusionBrood
## 独立艺术层，只消费动作事件并读取真实位移。
@onready var presentation: LargeFusionPresentation = $FusionPresentation
## 角色私有声音，死亡尾音交给既有共享池延续。
@onready var fusion_audio: LargeFusionAudio = $FusionAudio
## 防止强制消失入口提前设置 is_death 后漏结算或重复处理死亡。
var _death_processed: bool = false

## 使用专用头部锚点兼容既有命中与表现接口，展示时仅循环十二帧动作。
func _ready() -> void:
	head1_path_candidate.assign([NodePath("Body/HeadAnchor")])
	super()
	presentation.configure(self, rolling_attack, brood, fusion_audio)
	if character_init_type == E_CharacterInitType.IsNorm:
		fusion_audio.configure(self)
		brood.configure(self)
		rolling_attack.activate()

## 外部减速、冻结、眩晕、魅惑、恐惧、沉默与强制位移均不能改变其行动。
func can_receive_control_effects() -> bool:
	return false

## 寒冷值的累积入口与原生冰冻入口共用此免疫声明。
func can_receive_cold() -> bool:
	return false

## 只有自身撞击后的后抛处于原生空中态，外部位移免疫不阻止这条轨迹。
func is_native_airborne() -> bool:
	return is_instance_valid(rolling_attack) and rolling_attack.is_rebounding()

## 大体型沿地面碾压，不能被植物上的梯子切换为爬梯动作。
func start_climbing_ladder() -> void:
	pass

## 本物种有独立死亡快照，爆炸不再另造通用黑色尸体覆盖这段演出。
func _preserves_blast_death_animation() -> bool:
	return true

## 先停掉本体行为并登记后代，再发布死亡信号，避免短暂零敌人触发胜利。
func character_death() -> void:
	if _death_processed:
		return
	_death_processed = true
	presentation.release_death_visual()
	rolling_attack.finish_life()
	brood.resolve_death()
	super()
	queue_free()
