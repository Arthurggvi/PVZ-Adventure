## 雪人小鬼默认自由行走；推冰僵尸可在入树前给同一实体安装一次冰壳。
extends Zombie000Base
class_name Zombie031YetiImp

## 未受等阶影响的小鬼本体生命，供入树前冰甲成长取样。
const BASE_BODY_HP: float = 270.0
## 冰壳使用独立的一类非金属防具生命。
const BASE_ICE_HP: int = 600
## 自由小鬼走过一个实际种植格所需的基础动作秒数。
const SECONDS_PER_CELL: float = 4.0
## 碾压查询和地面位移执行器；运动进度由整条冰链的同一次推行持有。
@onready var _slide: FrozenImpSlide = $FrozenSlide
## 冰壳的后层、小鬼静帧与前层表现。
@onready var _ice_visual: FrozenImpVisual = $Body/FrozenVisual
## 原图动作播放器，破冰后继续用于同一只小鬼。
@onready var _source_sprite: AnimatedSprite2D = %SourceSprite
## 入树前配置的壳状态；正常自然生成保持 false。
var _frozen: bool = false
## 冰壳第一次露出视口的世界中心 X；仅在正式携带生成时设置。
var _entry_end_x: float = INF
## 推手已经退出护送；仍在场外且完成最后一次滑行后退场。
var _entry_abandoned: bool = false
## 同一时刻唯一拥有本冰块位移的整链推行节点。
var _ice_motion: Node
## 破甲回调到同步伤害结束之间的单次解冻门禁。
var _thaw_pending: bool = false
## 只释放冰壳亲自设置的移动锁，保留其他系统的既有锁。
var _owns_move_lock: bool = false
## 只释放冰壳亲自设置的攻击锁。
var _owns_attack_lock: bool = false
## 防止强制消失预先写入 is_death 后重复结算死亡。
var _death_processed: bool = false

## 入树前安装冰甲并记录 [param entry_end_x]；读取已绑定等阶，保留本体生命和死亡阈值。
func configure_frozen_spawn(entry_end_x: float) -> void:
	if is_inside_tree() or _frozen:
		return
	var health: HpComponentZombie = get_node(^"HpComponent") as HpComponentZombie # 入树前不能读取 onready 字段。
	var tier: Dictionary = AdventureZombieTierCatalog.get_tier(adventure_tier_id) # 等阶配置优先于体力比例回退。
	var multiplier: float = float(tier.get("armor", float(health.max_hp) / BASE_BODY_HP)) # 仅计算新装冰甲。
	health.max_hp_armor1 = maxi(1, roundi(float(BASE_ICE_HP) * multiplier))
	iron_type = IronType.Null
	_frozen = true
	_entry_end_x = entry_end_x

## 先接通原生生命及死亡链，再登记冰壳入场并启用冻结表现。
func _ready() -> void:
	head1_path_candidate.assign([NodePath("Body/HeadAnchor")])
	super()
	if not _frozen:
		return
	begin_right_entry(_entry_end_x)
	var health: HpComponentZombie = hp_component as HpComponentZombie # 正常受伤仍完全由原生生命组件结算。
	health.signal_armor1_death.connect(_on_ice_armor_broken)
	health.signal_hp_armor1_loss.connect(_on_ice_armor_loss)
	_lock_ice_actions()
	_set_ice_geometry(true)
	_ice_visual.show_armor(health, _source_sprite)
	if health.curr_hp_armor1 <= 0:
		_on_ice_armor_broken()

## 按当前棋盘实测格宽设置四秒一格；无可用战场时保留场景的基础速度。
func ready_norm() -> void:
	super()
	var game: MainGameManager = Global.main_game # 只读取本实例所属战场，不依赖图鉴预览。
	if is_instance_valid(game) and game.board != null and game.is_ancestor_of(self):
		var width: float = game.board.cell_width_at(global_position, lane) # 实际种植格的世界横向尺度。
		if width > 0.0:
			move_component.ori_speed = width / SECONDS_PER_CELL
			move_component.owner_update_speed(speed_factor_product())

## 返回是否仍为存活且冰甲未破的冰块；破甲信号发出后立即不再接受推力。
func is_frozen_block() -> bool:
	return _frozen and not _thaw_pending and not is_death and not is_queued_for_deletion()

## 返回世界空间中的冰壳半宽；碰撞和推链接触共用同一轮廓。
func ice_half_width() -> float:
	return FrozenImpVisual.ICE_HALF_WIDTH * absf(global_scale.x)

## 返回冰块是否已加入一条未结束的整链推行。
func is_ice_sliding() -> bool:
	return is_instance_valid(_ice_motion)

## [param motion] 已确认整链均未被占用；从本次推行开始重新记录碾压过的植物。
func claim_ice_motion(motion: Node) -> void:
	_ice_motion = motion
	_slide.begin_sweep()

## 返回本块是否仍由 [param motion] 持有；破甲或离场会同步解除归属。
func belongs_to_ice_motion(motion: Node) -> bool:
	return _ice_motion == motion and is_frozen_block()

## [param motion] 是本次唯一位移拥有者。[param distance] 是已裁到前块边缘的向左世界距离。
func advance_ice(motion: Node, distance: float) -> void:
	if belongs_to_ice_motion(motion):
		_slide.advance(-distance, is_frozen_block)

## [param motion] 只解除自己的推行归属；无人护送的场外冰块在最后一次推行结束后退场。
func release_ice_motion(motion: Node) -> void:
	if _ice_motion == motion:
		_ice_motion = null
		if _entry_abandoned:
			_retire_unarrived_ice.call_deferred()

## 结束出生推手的护送。已露出画面的冰壳可正常受击，破壳的小鬼自行走进战场。
func abandon_entry_escort() -> void:
	_entry_abandoned = true
	if not is_ice_sliding():
		_retire_unarrived_ice.call_deferred()

## 只有护送中断后仍完整、不可见且没有后续推力的冰壳退出战斗计数。
func _retire_unarrived_ice() -> void:
	if is_inside_tree() and is_frozen_block() and is_right_entry_pending() and not is_ice_sliding():
		retire_from_battle()

## 冰壳拒绝魅惑、外部位移和行动控制；破壳后恢复普通小鬼资格。
func can_receive_control_effects() -> bool:
	return not _frozen and not is_death and super()

## 冻结壳不积累寒冷值，也不接受普通或抗火冰冻。
func can_receive_cold() -> bool:
	return not _frozen and super()

## 冰块不会被植物上的梯子改写成爬梯轨迹。
func start_climbing_ladder() -> void:
	if not _frozen:
		super()

## 禁止本体移动与啃食，记录真正由冰壳新占用的锁。
func _lock_ice_actions() -> void:
	_owns_move_lock = not move_component.move_factors.get(MoveComponent.E_MoveFactor.IsCharacter, false)
	_owns_attack_lock = attack_component.is_enable_factors.get(ComponentNormBase.E_IsEnableFactor.Character, true)
	if _owns_move_lock:
		move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsCharacter)
	if _owns_attack_lock:
		attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	(anim_component as ImportedZombieAnimator).set_override(&"frozen")

## 仅撤销冰壳自己的锁；死亡、展示、战局暂停等禁用因素仍由原组件合成。
func _release_ice_actions() -> void:
	if _owns_move_lock:
		_owns_move_lock = false
		move_component.update_move_factor(false, MoveComponent.E_MoveFactor.IsCharacter)
	if _owns_attack_lock:
		_owns_attack_lock = false
		attack_component.enable_component(ComponentNormBase.E_IsEnableFactor.Character)
	(anim_component as ImportedZombieAnimator).clear_override()

## 原生零甲信号可能重复发出；第一次即停滑行，等整笔溢出伤害结束才尝试解冻。
func _on_ice_armor_broken() -> void:
	if not _frozen or _thaw_pending or _death_processed:
		return
	_thaw_pending = true
	_ice_motion = null
	call_deferred(&"_finish_thaw")

## 本次扣血若已致死或退场，不恢复活体；幸存时保留同一节点及全部原生状态。
func _finish_thaw() -> void:
	if not _thaw_pending or is_death or hp_component.is_death or is_queued_for_deletion() or retiring_from_battle:
		return
	_thaw_pending = false
	_frozen = false
	_ice_visual.hide_armor(_source_sprite)
	_set_ice_geometry(false)
	_release_ice_actions()

## [param frozen] 为真时使用整块冰的受击轮廓，破壳后恢复小鬼尺寸；延迟写形状兼容物理回调。
func _set_ice_geometry(frozen: bool) -> void:
	var outline: Shape2D # 本次所有检测层复用一个只读的实例专属形状。
	var center_y: float = -61.5 if frozen else -38.0 # 冰图按原标注尺寸校正后高约一百二十三像素。
	shadow.scale = Vector2(1.0, 0.65) if frozen else Vector2(0.65, 0.5)
	hp_component.position = Vector2(0.0, -122.0 if frozen else -72.0)
	if frozen:
		var rectangle: RectangleShape2D = RectangleShape2D.new() # 冰壳的原图显示尺寸。
		rectangle.size = Vector2(77.0, 123.0)
		outline = rectangle
	else:
		var capsule: CapsuleShape2D = CapsuleShape2D.new() # 自由小鬼的紧凑受击轮廓。
		capsule.radius = 18.0
		capsule.height = 76.0
		outline = capsule
	for path: NodePath in [^"HurtBoxComponent/HurtBoxDetection/CollisionShape2D",
			^"HurtBoxComponent/HurtBoxReal/CollisionShape2D",
			^"HurtBoxComponent/HurtBoxDetectionOnAttack/CollisionShape2D"]: # 保持检测层和真实命中层一致。
		var collider: CollisionShape2D = get_node(path) as CollisionShape2D # 当前需要切换的受击形状。
		collider.set_deferred(&"shape", outline)
		collider.set_deferred(&"position", Vector2(0.0, center_y))

## [param _armor]、[param _body_hp] 与 [param _drop] 保留原生命信号的参数，表现读取当前真实冰甲。
func _on_ice_armor_loss(_armor: int, _body_hp: int, _drop: bool) -> void:
	if _frozen and not _thaw_pending:
		_ice_visual.refresh_armor(hp_component as HpComponentZombie)

## 先封锁死亡行动再清理冰壳；清场和同击致死均不能短暂恢复啃食或重新生成小鬼。
func character_death() -> void:
	if _death_processed:
		return
	_death_processed = true
	_ice_motion = null
	move_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	_frozen = false
	_thaw_pending = false
	_ice_visual.hide_armor(_source_sprite)
	_set_ice_geometry(false)
	_release_ice_actions()
	super()

## 离树后不保留可再次推进的轨迹；普通换行也不能重新播放旧余程。
func _exit_tree() -> void:
	_ice_motion = null
