## 战斗机的分层飞行、枪焰与击毁爆炸表现。
extends Node
class_name FighterPresentation

## 载具共用的击毁火球、冲击波、烟尘和分段爆声演出。
const VehicleDeathBlast := preload("res://scripts/character/zombie/vehicle_death_blast.gd")
## 按轻型机体约减半缩放，保持爆炸主体与单行机身相称。
const DEATH_BLAST_SCALE: float = 0.46

## 实际逐帧机体图集（飞行和开火有不同纹理，非单帧上下摇摆）。
@onready var sprite: AnimatedSprite2D = %SourceSprite
## 源贴图动画仍由原通用动画入口控制暂停、动作速度和死亡阶段。
@onready var animator: ImportedZombieAnimator = %AnimComponent
## 从原作开火画中提取的枪焰，与完整飞机贴图互不覆盖。
@onready var muzzle: AnimatedSprite2D = %MuzzleFlash
## 复用初代气球零件素材的前侧旋翼。
@onready var rotor: Sprite2D = %Rotor
## 低透明度旋翼叠层，模拟高速旋转的扫掠残影。
@onready var rotor_blur: Sprite2D = %RotorBlur
## 真正的枪口坐标，与机体原画坐标及旋转一致。
@onready var muzzle_marker: Marker2D = %MuzzleMarker
## 可见机身中心，供出舱轨迹对位和击毁主火球定位。
@onready var blast_origin: Marker2D = %DeathBlastOrigin
## 每发开火后复位至飞行动作，不截断其他射击事件。
@onready var fire_timer: Timer = $FireTimer
## 所属实体只提供寿命与行动倍率，不由表现层结算伤害。
var _fighter: Zombie000Base
## 飞行姿态与旋翼使用同一随场景暂停的时间源。
var _hover_time: float = 0.0

## 设置动作事件；不在展示模式启动武器或声音。
func configure(fighter: Zombie000Base) -> void:
	_fighter = fighter
	fire_timer.timeout.connect(_finish_fire)
	muzzle.animation_finished.connect(_finish_muzzle)
	set_process(true)

## [param delta] 机体与驾驶员纹理每帧推进，旋翼独立快速自转。
func _process(delta: float) -> void:
	if not is_instance_valid(_fighter) or _fighter.is_death:
		return
	var rate: float = _fighter.action_rate() # 受现有动作减速和游戏暂停控制。
	_hover_time += delta * rate
	rotor.rotation += delta * 35.0 * rate
	rotor_blur.rotation -= delta * 52.0 * rate
	rotor.scale.x = 1.65 * (0.78 + 0.22 * absf(cos(_hover_time * 29.0)))
	sprite.position.y = sin(_hover_time * 3.2) * 1.2
	sprite.rotation = sin(_hover_time * 2.8 + 0.5) * 0.009

## 返回实际枪口世界坐标，弹丸和枪焰必须共用这个变换。
func muzzle_world_position() -> Vector2:
	return muzzle_marker.global_position

## 每发枪弹立刻触发：机体反冲帧 + 独立枪焰 6 帧 + 枪口世界坐标。
func fire() -> void:
	if not is_instance_valid(_fighter) or _fighter.is_death:
		return
	animator.set_override(&"fire", 0.18)
	muzzle.visible = true
	muzzle.stop()
	muzzle.frame = 0
	muzzle.play(&"flash")
	fire_timer.start(0.18)

## 在原死亡爆点播放一次主爆，返回可绑定实际残骸的飞艇事件序号。
func play_death_blast() -> int:
	if not is_instance_valid(_fighter):
		return 0
	var size: float = DEATH_BLAST_SCALE * _fighter.transform.x.length() # 小僵尸模式沿用机体缩放。
	var facing: float = float(_fighter.direction_x_root) # 默认向左，反向时交换机头和机尾的横向偏移。
	var followups: PackedVector2Array = PackedVector2Array([
		Vector2(-109.0 * facing, 12.0), Vector2(101.0 * facing, 24.0),
	]) # 两次余爆依次沿机头和机尾亮起。
	var parts := PackedVector2Array([rotor.global_position, blast_origin.to_global(Vector2(47.0, -11.0))]) # 机头轴与机尾支架，随快照姿态移动。
	return VehicleDeathBlast.play(_fighter, &"fighter_death_blast", blast_origin.global_position, size, followups, parts)


## 当前枪焰已经完全播放，避免无目标或枪口暂停时残留火光。
func _finish_muzzle() -> void:
	muzzle.hide()

## 只有临时开火动作到期才撤销覆盖，返回真实飞行帧而非待机单张图。
func _finish_fire() -> void:
	animator.clear_override()

## 击毁或吹离共用一次清理，退出后不再驱动旋翼及火光。
func finish_life() -> void:
	set_process(false)
	fire_timer.stop()
	muzzle.hide()
	animator.clear_override()
