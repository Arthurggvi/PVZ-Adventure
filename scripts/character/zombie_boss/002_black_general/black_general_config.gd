## 黑将军战斗数值；动画时长由美术时间轴提供，不在技能代码内复制。
extends Resource
class_name BlackGeneralConfig

## 狂暴前动作结束至下一动作的等待秒数。
@export var phase_one_action_interval: float = 5.0
## 狂暴后动作结束至下一动作的等待秒数。
@export var phase_two_action_interval: float = 4.0
## 两次成功插旗之间的最短战斗秒数。
@export var flag_cooldown: float = 20.0
## 冲锋速度，单位像素/秒，受角色减速影响。
@export var charge_speed: float = 300.0
## 换行跑步速度，单位像素/秒。
@export var lane_change_speed: float = 140.0
## 每株植物每次冲锋受到的伤害。
@export var charge_damage: int = 1800
## 一阶段冲锋撞死植物上限；阶段二与转阶段不使用上限。
@export var phase_one_kill_limit: int = 2
## 乘以场地行数得到号令援军总量，实际行号由波次系统分配。
@export var command_per_lane: int = 2
## 号令使用的普通僵尸池，等阶在释放时由阶段决定。
@export var command_types: Array[CharacterRegistry.ZombieType] = [
	CharacterRegistry.ZombieType.Z001Norm, CharacterRegistry.ZombieType.Z003Cone,
	CharacterRegistry.ZombieType.Z004PoleVaulter, CharacterRegistry.ZombieType.Z005Bucket,
	CharacterRegistry.ZombieType.Z008Football]
## 令旗生命值。
@export var flag_health: int = 3000
## 第一阶段令旗格挡。
@export var phase_one_block: int = 10
## 第二阶段令旗格挡。
@export var phase_two_block: int = 20
