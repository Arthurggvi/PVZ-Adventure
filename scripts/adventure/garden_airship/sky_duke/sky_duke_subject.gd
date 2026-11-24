## 一个已登记公爵的动作表现状态。只读实体属性，不驱动血量、技能或行动。
extends RefCounted

## 当前正式 Boss 派生对象和只读动作时间接口。
const Duke := preload("res://scripts/character/zombie_boss/sky_duke/z_b_007_sky_duke.gd")
## 两种号令的实际原画手指锚点与传送的躯体中心，均为 Boss 根节点局部像素。
const MARKS := {
	&"command": Vector2(-88, -159),
	&"sky_order": Vector2(-43, -206),
}
## 角色稳定漂浮中心，为阶段波和传送共用。
const CENTER := Vector2(0, -108)
## 角色待机气爆的预收束时间，单位为战斗秒。
const GATHER_SECONDS := 0.22

## 由 ZombieManager 提供的实际 Boss 实例。
var actor: Duke
## 当局顺序，由场景导演生成的确定性种子。
var seed_value: int
## 当前正在播放的美术动作。
var action: StringName = &"idle"
## 当前动作的号令事件已接收。
var cue_seen: bool = false
## 传送前兆的吸入是否已经处理。
var inhaled: bool = false
## 传送收束前的世界压波是否已经交付。
var collapsed: bool = false
## 人物已完成消隐。场地中已经释放的余波不受此量影响。
var departed: bool = false
## 当前装饰性气爆是否已经释放。
var pressure_released: bool = false
## 本轮待机气爆释放时刻，没有可见气爆时为 INF。
var _pulse_at: float = INF
## 关卡私有随机流，验收可固定而不改实际出怪随机数。
var _random := RandomNumberGenerator.new()


## 为 [param host] 登记演出，使用 [param stable_seed] 隔离装饰性气爆的随机序列。
func _init(host: Duke, stable_seed: int) -> void:
	actor = host
	seed_value = stable_seed
	_random.seed = stable_seed


## [param name_of_action] 来自已开播的新动作。每次进入给该轮独立的去重状态。
func begin(name_of_action: StringName) -> void:
	action = name_of_action
	cue_seen = false
	inhaled = false
	collapsed = false
	if name_of_action == &"idle":
		departed = false
	_reset_pulse()


## 结束 [param name_of_action] 的蓄势与导向，传送后一直保持环境人物隐藏。
func finish(name_of_action: StringName) -> void:
	if action != name_of_action:
		return
	departed = name_of_action == &"teleport_out"
	action = &"idle"


## 读取 [param seconds] 时相。其它实装动作或冲击开启时 [param blocked] 会取消装饰性气爆。
## 返回收束开始后的动作秒数，负值代表正常待机。
func idle_pressure_age(seconds: float, blocked: bool) -> float:
	if blocked or actor.boss_phase < 2 or action != &"idle" or departed or not actor.is_visible_in_tree():
		_reset_pulse()
		return -1.0
	if seconds >= _pulse_at + 0.39:
		_reset_pulse()
	if _pulse_at == INF:
		_pulse_at = seconds + _random.randf_range(3.05, 5.45)
	return seconds - _pulse_at + GATHER_SECONDS


## 返回 [param kind] 对应的手指或胸口世界锚点，适应 Boss 节点的实际朝向。
func origin(kind: StringName) -> Vector2:
	return actor.to_global(MARKS.get(kind, CENTER))


## 返回 [param kind] 的世界传播方向，与 Boss 的水平镜像相容。
func axis(kind: StringName) -> Vector2:
	var local_axis: Vector2 = Vector2.UP if kind == &"sky_order" else Vector2.LEFT # 纵向信号和左向阵线各自独立。
	return actor.global_transform.basis_xform(local_axis).normalized()


## 当前动作的 [param age] 下，环境蓄力压暗窗口的归一权重。
func anticipation(age: float) -> float:
	match action:
		&"command": return _charge(age, 0.19, 0.40)
		&"sky_order": return _charge(age, 0.27, 0.50)
		&"teleport_out": return _charge(age, 1.39, 1.65) * 0.85
	return 0.0


## 对 [param elapsed] 的 [param start_seconds] 到 [param end_seconds] 区间做平滑收束。
func _charge(elapsed: float, start_seconds: float, end_seconds: float) -> float:
	return smoothstep(start_seconds, start_seconds + 0.10, elapsed) * (1.0 - smoothstep(end_seconds, end_seconds + 0.06, elapsed))


## 清除尚未发生的装饰气爆，不触动已经分离的世界效果。
func _reset_pulse() -> void:
	_pulse_at = INF
	pressure_released = false
