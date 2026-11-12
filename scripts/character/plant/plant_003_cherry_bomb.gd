extends Plant000Base
class_name Plant003CherryBomb

## 种下到引爆的战斗秒数，与膨胀动画的播放速度独立。
const FUSE_SECONDS := 1.0
## 原版膨胀动画以 10–15 帧每秒播放；导入轨道以 30 帧每秒取样。
const FUSE_ANIMATION_SPEED := 12.5 / 30.0
## 种下后立即播放的吸气音效。
const FUSE_SFX := preload("res://assets/audio/sounds/reverse_explosion.ogg")
## 结算一次圆形爆炸伤害并启动爆炸表现。
@onready var bomb_component: BombComponentNorm = %BombComponent
## 仅出战时启动的一次性引信，受战斗暂停和全局速度控制。
@onready var fuse_timer: Timer = $FuseTimer
## 此出战实例的来源卡与转职词条，种植前由冻结快照注入。
var _source_uid: String
var _promotion_effects: Array[Dictionary] = []

## 保存 [param uid] 和 [param effects]，仅在原引信引爆时创建后续战斗效果。
func configure_promotions(uid: String, effects: Array[Dictionary]) -> void:
	_source_uid = uid
	_promotion_effects = effects

## 种下后开始膨胀和引信；展示与花园沿用待机动画。
func ready_norm() -> void:
	super()
	anim_component.set_animation_origin_speed(FUSE_ANIMATION_SPEED)
	if not _promotion_effects.is_empty():
		# 转职区域从物理空间查询，首爆和追爆都在物理帧结算。
		fuse_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	fuse_timer.timeout.connect(_detonate)
	bomb_component.signal_bomb_once.connect(_finish_blast)
	fuse_timer.start(FUSE_SECONDS)
	SoundManager.play_sfx_with_pool(FUSE_SFX)

## 引信到时结算爆炸并移除植物；提前移除的植物不会补炸。
func _detonate() -> void:
	if is_death or is_queued_for_deletion():
		return
	if bomb_component.is_enabling and not bomb_component.is_bomb and not _promotion_effects.is_empty():
		# 追爆和地火必须由战场持有，母株爆炸后仍按原流程移除。
		var blast := AdventureCherryBlast.new()
		if blast.configure(self, bomb_component, _source_uid, _promotion_effects):
			Global.main_game.bombs.add_child(blast)
			bomb_component.damage_resolver = blast.detonate
		else:
			blast.free()
	bomb_component.bomb_once()
	character_death()

## 普通炸弹清除种植格及相邻格子的梯子，转职爆炸按自己的范围处理。
func _finish_blast() -> void:
	if not bomb_component.damage_resolver.is_valid() and is_instance_valid(plant_cell):
		# 未转职的樱桃仍清除原来的邻格范围。
		for cell: PlantCell in plant_cell.get_plant_cell_surrounding():
			if is_instance_valid(cell.ladder):
				cell.ladder.ladder_death()

## 引爆前可吸引僵尸停下啃咬，但啃咬不扣除樱桃炸弹的生命值。
## [param _attack_value] 本次啃咬伤害，由引信期间的保护忽略。
## [param _attack_zombie] 发起啃咬的僵尸。
func be_zombie_eat(_attack_value: int, _attack_zombie: Zombie000Base) -> void:
	pass

## 冰车和投篮车从樱桃炸弹上开过时不会压掉引信。
## [param character] 发起碾压或砸击的角色；其他来源走普通压扁流程。
func be_flattened_from_enemy(character: Character000Base) -> void:
	if character is Zombie013Zamboni or character is Zombie023Catapult:
		return
	super(character)
