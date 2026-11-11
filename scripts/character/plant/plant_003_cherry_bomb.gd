extends Plant000Base
class_name Plant003CherryBomb

## 种下到引爆的战斗秒数，与膨胀动画的播放速度独立。
const FUSE_SECONDS := 1.0
## 原版膨胀动画以 10–15 帧每秒播放；导入轨道以 30 帧每秒取样。
const FUSE_ANIMATION_SPEED := 12.5 / 30.0
## 种下后立即播放的吸气音效。
const FUSE_SFX := preload("res://assets/audio/sounds/reverse_explosion.ogg")
## 与爆炸主音效同帧播放的果肉迸裂声。
const BURST_SFX := preload("res://assets/audio/sounds/juicy.ogg")

## 结算一次圆形爆炸伤害并启动爆炸表现。
@onready var bomb_component: BombComponentBase = %BombComponent
## 仅出战时启动的一次性引信，受战斗暂停和全局速度控制。
@onready var fuse_timer: Timer = $FuseTimer

## 种下后开始膨胀和引信；展示与花园沿用待机动画。
func ready_norm() -> void:
	super()
	anim_component.set_animation_origin_speed(FUSE_ANIMATION_SPEED)
	fuse_timer.timeout.connect(_detonate)
	bomb_component.signal_bomb_once.connect(_finish_blast)
	fuse_timer.start(FUSE_SECONDS)
	SoundManager.play_sfx_with_pool(FUSE_SFX)

## 引信到时结算爆炸并移除植物；提前移除的植物不会补炸。
func _detonate() -> void:
	if is_death or is_queued_for_deletion():
		return
	bomb_component.bomb_once()
	character_death()

## 播放叠加音效，并清除种植格及相邻格子的梯子。
func _finish_blast() -> void:
	SoundManager.play_sfx_with_pool(BURST_SFX)
	if is_instance_valid(plant_cell):
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
