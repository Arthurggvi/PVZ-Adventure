## 单株冻结的电球转职参数，可由同一次离手的电球与所有后代共享。
extends RefCounted
class_name ElectricPeaPromotions

## 飞行速度比例；未选电荷牵引时为一。
var speed_multiplier: float = 1.0
## 每轮原始放电名额；跳跃不占用此名额。
var bolt_targets: int = 2
## 跳跃允许的横向格数；零表示未选择。
var jump_cells: float = 0.0
## 分道到达相邻行需要的横向格数；零表示只发中路。
var spread_cells: float = 0.0
## 每次实际攻击命中的眩晕秒数。
var stun_seconds: float = 0.0
## 首次实伤直击分出的子弹数；零表示未选择。
var split_count: int = 0
## 首次实伤直击附加的眩晕秒数。
var split_stun: float = 0.0
## 小电球相对于离手伤害的比例。
var split_damage: float = 1.0
## 小电球相对于标准电球的外观及碰撞边长比例。
var split_size: float = 1.0
## 矩阵每个固定结算帧的基础伤害；零表示未选择。
var matrix_damage: int = 0
## 共生每株相邻雷电植物增加的输出比例。
var neighbor_bonus: float = 0.0


## 将实际出战的 [param events] 冻结成电球参数；未选择的技能保持默认行为。
func _init(events: Array[Dictionary]) -> void:
	for event: Dictionary in events: # 各阶互斥已由研究目录校验。
		match String(event.kind):
			"electric_pea_charge_pull":
				speed_multiplier = float(event.speed_multiplier)
			"electric_pea_static_cling":
				bolt_targets = int(event.targets)
			"electric_pea_arc_jump":
				jump_cells = float(event.cells)
			"electric_pea_spread":
				spread_cells = float(event.spread_cells)
			"electric_pea_overload":
				stun_seconds = float(event.seconds)
			"electric_pea_pulse_split":
				split_count = int(event.count)
				split_stun = float(event.seconds)
				split_damage = float(event.damage_multiplier)
				split_size = float(event.size_multiplier)
			"electric_pea_matrix":
				matrix_damage = int(event.damage)
			"electric_pea_symbiosis":
				neighbor_bonus = float(event.bonus)