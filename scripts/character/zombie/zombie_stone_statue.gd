## 固定石壳的生命周期；破壳后由同等阶普通僵尸真实接替，原壳不产生击杀或掉落。
extends Zombie001Norm
class_name ZombieStoneStatue

## 纯视觉节点与普通身体同级，旧壳退场前将碎片转交到战场行。
@onready var stone_visual: StoneStatueVisual = $StoneStatueVisual
## 独立石壳生命组件，封存生命只作为自然波次预算，不参与本次伤害结算。
@onready var stone_health: HpComponentStoneStatue = $HpComponent
## 出生所在战场，异步破壳不允许进入另一场战斗。
var _birth_game: MainGameManager
## 出生轮次，续战清理期间不补生旧石像内的普僵。
var _birth_round: int = -1
## 出生冒险阶段，旧阶段的破壳回调不得污染新阶段。
var _birth_phase: StagePhaseDefinition
## 成功换体后封存预算归新实体所有，旧壳后续不再扣除。
var _converted: bool = false
## 真正死亡时只扣除一次封存生命，不依赖调用者提前设置的 is_death 顺序。
var _contained_budget_released: bool = false

## 保留普通碰撞、受击及波次信号；冻结动作并用石像遮住普通身体。
func _ready() -> void:
	super()
	body.hide()
	modulate = Color.WHITE
	move_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	anim_component.stop_anim()
	swim_box_component.lock_swim_pose()
	is_walk = false
	stone_health.shell_broken.connect(_queue_release)
	stone_health.signal_hp_loss.connect(_on_shell_health_changed)
	stone_visual.scale.x = absf(stone_visual.scale.x) * direction_x_body
	signal_direction_x_body_update.connect(_sync_stone_direction)
	if character_init_type == E_CharacterInitType.IsNorm:
		_birth_game = Global.main_game
		_birth_round = _birth_game.curr_game_round
		_birth_phase = AdventureSession.get_active_phase(_birth_game.game_para)
		stone_visual.play_arrival()

## [param direction] 为身体方向；只同步视觉，不改变脚点或碰撞盒。
func _sync_stone_direction(direction: int) -> void:
	stone_visual.scale.x = absf(stone_visual.scale.x) * signi(direction)

## [param remaining] 是石壳剩余生命；[param _drop] 不产生普通头手掉落。
func _on_shell_health_changed(remaining: int, _drop: bool) -> void:
	stone_visual.set_integrity(float(remaining) / float(HpComponentStoneStatue.SHELL_HEALTH))

## 伤害路由完整退出后再换体，避免同一爆炸遍历到新生普僵或提前改变本击回执。
func _queue_release() -> void:
	_release_zombie.call_deferred()

## 只有原战场仍在进行时执行一次换体；先登记新体，再注销旧壳，避免瞬间误判清场。
func _release_zombie() -> void:
	if _converted or is_death or is_queued_for_deletion() or not stone_health.can_release_zombie() \
			or curr_be_attack_status == E_BeAttackStatusZombie.IsDraggedUnder:
		return
	if not is_instance_valid(_birth_game) or _birth_game != Global.main_game \
			or not _birth_game.is_ancestor_of(self) or _birth_game.curr_game_round != _birth_round \
			or AdventureSession.get_active_phase(_birth_game.game_para) != _birth_phase:
		return
	var manager: ZombieManager = _birth_game.zombie_manager # 仍属于原局的管理器负责实体和波次交接。
	if not manager.is_game_running() or lane < 0 or lane >= manager.all_zombie_rows.size():
		return
	var row: ZombieRow = manager.all_zombie_rows[lane] # 保持石像所在行，不重新随机选格。
	var spawn_position: Vector2 = global_position # 新普僵 ready 会重新补坡度，因此先减去同一高度。
	if is_instance_valid(_birth_game.main_game_slope):
		var slope_y: float = _birth_game.main_game_slope.get_all_slope_y(global_position.x) # 当前位置的坡面高度。
		spawn_position -= row.get_global_transform().basis_xform(Vector2(0.0, slope_y))
	var parameters: Dictionary = { # 身份来自原石像，禁止恢复默认波次或默认迷你设置。
		E_ZInitAttr.CharacterInitType: E_CharacterInitType.IsNorm,
		E_ZInitAttr.Lane: lane,
		E_ZInitAttr.CurrWave: curr_wave,
		E_ZInitAttr.CurrZombieRowType: curr_zombie_row_type,
		E_ZInitAttr.IsMiniZombie: is_mini_zombie,
		E_ZInitAttr.IsZombieMode: is_zombie_mode,
		E_ZInitAttr.ParticipatesNaturalRefresh: participates_natural_refresh,
	}
	var modifier: ZombieSpawnModifier = AdventureZombieTierBinding.new(adventure_tier_id) \
		if adventure_tier_id != &"" else null # 空等阶的原版石像释放原版普僵。
	var released: Zombie000Base = manager.create_norm_zombie(CharacterRegistry.ZombieType.Z001Norm,
		row, parameters, spawn_position, Callable(), modifier, null, self) # 新体沿用石壳的在场名额并以满血出场。
	if not is_instance_valid(released):
		push_error("石像换体失败：同等阶普通僵尸未能创建")
		return
	manager.zombie_wave_manager.replace_stone_statue_with_zombie(self, released)
	_converted = true
	stone_visual.shatter(row)
	manager.retire_converted_zombie(self)

## 返回同阶普僵的封存生命；换体或真正死亡后由原波次交接过程移除。
func contained_zombie_wave_health() -> int:
	return 0 if _converted or _contained_budget_released else stone_health.contained_body_hp

## 真正强制死亡时同时清除封存预算；破壳转换不会走到这个入口。
func character_death() -> void:
	var contained_health: int = contained_zombie_wave_health() # 强制消失可能已先设置 is_death，仍需消费预算。
	_contained_budget_released = true
	super()
	if contained_health > 0:
		signal_zombie_hp_loss.emit(contained_health, curr_wave)
	_fade_and_remove() # 石像已停用动画树，真正死亡仍须有独立退场；碾压或直接删除会提前结束此补间。

## 石壳不能被魅惑；破壳后的普通僵尸使用原生魅惑规则。
func be_hypno() -> void:
	pass
