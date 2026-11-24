## 火箭小鬼的索敌、啃咬和受击沿用陆地僵尸规则；死亡后立即交接外观。
extends Zombie000Base
class_name Zombie041RocketImp

## 出生时可装备的三种互斥形态，取值连续以便等概率抽选。
enum SpawnArmor {
	Bare, ## 裸头，没有额外防具血池。
	Cone, ## 塑料路障，使用一类防具血池。
	Bucket, ## 铁桶，使用一类防具血池并允许磁力菇吸取。
}

## 克隆在原生生成参数中传递的头盔种类键。
const SPAWN_ARMOR_OVERRIDE: StringName = &"rocket_imp_spawn_armor"
## 路障的一阶防具生命，与原生路障僵尸一致。
const CONE_ARMOR_HP: int = 370
## 铁桶的一阶防具生命，等阶绑定会在角色入树前缩放该上限。
const BUCKET_ARMOR_HP: int = 1100

## 满血路障，实例场景加载时与逐帧角色一起取得。
@export var cone_armor_texture: Texture2D
## 满血铁桶，实例场景加载时与逐帧角色一起取得。
@export var bucket_armor_texture: Texture2D
## 路障在两档损伤及破甲时的原生外观变化。
@export var cone_armor_changes: Array[ResourceBodyChange]
## 铁桶在两档损伤及破甲时的原生外观变化。
@export var bucket_armor_changes: Array[ResourceBodyChange]

## 初始头盔种类，破甲后仍由战斗克隆用于还原原形态。
var spawn_armor: SpawnArmor = SpawnArmor.Bare

## 按战斗状态切换逐帧动作，并检查咬合反馈和死亡交接。
@onready var _presentation: RocketImpPresentation = %AnimComponent
## 第一次死亡入口即锁定，保护原生掉血、等阶和战场移除流程。
var _death_processed: bool = false


## 读取 [param zombie_init_para] 中的出生参数；实战新生实例等概率选一件防具。
## 在等阶绑定及生命组件就绪前装备；战斗克隆使用快照指定的原形态。
func init_zombie(zombie_init_para: Dictionary) -> void:
	super(zombie_init_para)
	if character_init_type != E_CharacterInitType.IsNorm:
		return

	var armor: SpawnArmor # 正常新生实例的随机结果，或复制实例的原始头盔。
	if zombie_init_para.has(SPAWN_ARMOR_OVERRIDE):
		armor = int(zombie_init_para[SPAWN_ARMOR_OVERRIDE]) as SpawnArmor
	else:
		armor = randi_range(SpawnArmor.Bare, SpawnArmor.Bucket) as SpawnArmor
	_equip_spawn_armor(armor)


## 装备 [param armor] 指定的一类防具，沿用原生受击、破甲及铁器判定。
func _equip_spawn_armor(armor: SpawnArmor) -> void:
	spawn_armor = armor
	if armor == SpawnArmor.Bare:
		return

	var metal: bool = armor == SpawnArmor.Bucket # 铁桶使用铁器音效和磁力菇入口。
	var health: HpComponentZombie = $HpComponent # 入树前只设置基础上限，当前血量由组件初始化。
	health.max_hp_armor1 = BUCKET_ARMOR_HP if metal else CONE_ARMOR_HP
	health.sfx_be_attack_armor1 = SoundManagerClass.TypeBeAttackSFX.Shield if metal else SoundManagerClass.TypeBeAttackSFX.Plastic
	var stages: HpStageChangeComponent = $HpStageChangeComponent # 额外防具按缩放后的满血生成破损阈值。
	stages.body_change_armor1 = bucket_armor_changes if metal else cone_armor_changes

	var helmet: Sprite2D = $Body/HeadAnchor/HeadArmor # 与身体一起翻转和染色的头部贴图。
	helmet.texture = bucket_armor_texture if metal else cone_armor_texture
	helmet.position = Vector2(11, -23) if metal else Vector2(10, -27)
	helmet.show()

	var anchor: Marker2D = $Body/HeadAnchor # 将头饰的局部位置换算到身体的掉落物容器。
	var debris: Sprite2D = $Body/NodeDrop/HeadArmorDrop/Sprite # 破损换图与头饰同步的脱落部件。
	debris.texture = helmet.texture
	debris.transform = helmet.transform
	debris.position += anchor.position

	if metal:
		iron_type = IronType.IronArmor1
		iron_node.transform = helmet.transform


## 逐帧素材以标记节点提供头部坐标，供原有状态特效定位。
func _ready() -> void:
	head1_path_candidate.assign([NodePath("Body/HeadAnchor")])
	super()


## 花园实例与普通预览一样只播放待机动画。
func ready_garden() -> void:
	super()
	move_component.disable_component(ComponentNormBase.E_IsEnableFactor.InitType)
	attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.InitType)


## 灰烬伤害也使用物种自身的坠落帧。
func _preserves_blast_death_animation() -> bool:
	return true


## 先快照受击时的姿态，再由基类结算死亡；直接清场时不生成坠落外观。
func character_death() -> void:
	if _death_processed:
		return
	_death_processed = true
	_presentation.stop_anim()
	if not is_death:
		_presentation.handoff_death()
	move_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	super()
	queue_free()
