## 穴居僵尸：复用原伤害/断肢阶段，只把推冰和出生冰链交给独立组件。
extends Zombie000Base
class_name Zombie030Troglobite

## 正常步行每格所需秒数；推冰动作的停步不计入步行速度。
const WALK_SECONDS_PER_CELL: float = 5.5
## 推冰动作、接触检查和断手停推的唯一状态拥有者。
@onready var ice_push: TroglobitePush = $IcePush
## 编排本次离屏入场，并负责未入场冰块的护送生命周期。
@onready var ice_train: TroglobiteIceTrain = $IceTrain
## 防止清场与伤害同时到达时重复发布本体死亡。
var _death_processed: bool = false

## 在原生初始化前配置头部接口，供出战和展示共用。
func _ready() -> void:
	head1_path_candidate.assign([NodePath("Body/HeadAnchor")])
	super()

## 正式出战先布置右侧入场位置，再让原生初始化按该位置修正坡面。
func ready_norm() -> void:
	ice_push.pushing_ended.connect(ice_train.end_escort)
	ice_train.configure(self)
	super()
	var game: MainGameManager = Global.main_game # 场外位置仍取该行最近的实际格宽。
	if not is_instance_valid(game) or game.board == null or not game.is_ancestor_of(self):
		return
	var width: float = game.board.cell_width_at(global_position, lane) # 当前棋盘实际格宽。
	if width > 0.0:
		move_component.ori_speed = width / WALK_SECONDS_PER_CELL
		move_component.owner_update_speed(speed_factor_product())
	ice_push.configure(self)

## 只抵抗完全冰封；原生寒冷入口自动转换为同等总时长的半速。
func can_cold_freeze() -> bool:
	return false

## 推冰的大体型不切入没有原动画的爬梯姿态。
func start_climbing_ladder() -> void:
	pass

## 已有原版倒地帧；爆炸不另叠没有对应部件的通用灰烬尸体。
func _preserves_blast_death_animation() -> bool:
	return true

## 先关闭本体的推冰和行走，再由原生命通路通知计数、掉落与原帧死亡动画。
func character_death() -> void:
	if _death_processed:
		return
	_death_processed = true
	ice_push.finish_life()
	move_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	super()
