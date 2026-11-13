## 原版产阳光组件；实际生产事件与额外奖励分离，避免亡语奖励再次计入生产储蓄。
extends ComponentNormBase
class_name CreateSunComponent

## 生产阳光计时器，周期保存为正常角色速度下的秒数。
@onready var create_sun_timer: SpeedTimer = $CreateSunTimer
## 身体节点，负责生产前后的短暂发光。
@onready var body: BodyCharacter = %Body

## 每份普通阳光基础价值。
@export var sun_value: int = 25
## 本株实际抛出阳光的位置。
@export var marker_2d_create_sun: Marker2D
## 每轮普通阳光份数。
@export var num_create_sun: int = 1
## 冻结转职规定的每轮额外小阳光最少份数。
var extra_small_sun_min: int = 0
## 冻结转职规定的每轮额外小阳光最多份数。
var extra_small_sun_max: int = 0
## 每轮生产完成后累加的单份价值。
var production_growth_step: int = 0
## 单份生产成长加值的上限。
var production_growth_cap: int = 0
## 当前已积累的生产成长加值，不回写出战卡。
var _production_growth_bonus: int = 0

@export_group("生产间隔时间")
## 首轮生产的基础秒数范围。
@export var create_time_range_first: Vector2 = Vector2(3, 12.5)
## 后续生产的基础秒数范围。
@export var create_time_range_other: Vector2 = Vector2(23.5, 25)
## 当前完整生产间隔，始终以正常角色速度下的秒数保存。
var create_interval: float
## 本株所有产出共用的表现材质；空值保留原版阳光外观。
var sun_visual_material: Material

## [param total_value] 是本轮已实际创建的全部生产阳光总值；不包括奖励或储蓄提现。
signal production_created(total_value: int)

@export_group("我是僵尸模式")
## 原版受击和死亡仍可释放的阳光份数。
@export var remaining_sun_on_zombie_mode: int = 8

## 原版我是僵尸模式每次受击消耗一份待产出阳光。
func _on_be_eat_once() -> void:
	if remaining_sun_on_zombie_mode > 0:
		remaining_sun_on_zombie_mode -= 1
		_spawn_sun()

## 原版我是僵尸模式在角色发出死亡信号前释放剩余产出。
func _on_character_death() -> void:
	if remaining_sun_on_zombie_mode > 0:
		for _index: int in range(remaining_sun_on_zombie_mode): # 每份仍沿用完整生产流程。
			_spawn_sun()
		remaining_sun_on_zombie_mode = 0

## 保存首轮基础周期和速度；展示场景不启动生产。
func _ready() -> void:
	create_interval = randf_range(create_time_range_first.x, create_time_range_first.y)
	create_sun_timer.base_wait_time = create_interval
	owner_update_speed(GlobalUtils.get_dic_product(owner.influence_speed_factors))
	if not get_tree().current_scene is MainGameManager:
		return
	create_sun_timer.start_scaled()
	EventBus.subscribe("main_game_progress_update", _on_main_game_progress_update)

## [param curr_main_game_progress] 为当前战斗阶段，仅正式战斗启用生产。
func _on_main_game_progress_update(curr_main_game_progress: MainGameManager.E_MainGameProgress) -> void:
	if curr_main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
		enable_component(E_IsEnableFactor.MainGameProgress)
	else:
		disable_component(E_IsEnableFactor.MainGameProgress)

## [param is_enable_factor] 是本次允许原因；所有门禁允许时沿用原版完整周期重启。
func enable_component(is_enable_factor: E_IsEnableFactor) -> void:
	super(is_enable_factor)
	if is_enabling:
		create_sun_timer.start_scaled()

## [param is_enable_factor] 是本次禁止原因；睡眠或战斗结束仍停止原版计时。
func disable_component(is_enable_factor: E_IsEnableFactor) -> void:
	super(is_enable_factor)
	if not is_enabling:
		create_sun_timer.stop()

## [param speed_product] 为角色速度乘积；禁用期间也同步倍率，零速保留计时任务。
func owner_update_speed(speed_product: float) -> void:
	create_sun_timer.set_speed_scale(speed_product)

## 每轮生产后抽取后续基础间隔，并重新启动原版计时器。
func change_production_interval() -> void:
	create_interval = randf_range(create_time_range_other.x, create_time_range_other.y)
	create_sun_timer.start_scaled(create_interval)

## 只允许存活本株完成正常生产；睡眠、死亡和退场后的晚到发光回调不再产出。
func _spawn_sun() -> void:
	if not _can_spawn_sun(false) or (not is_enabling and not owner.is_zombie_mode):
		return
	SoundManager.play_character_SFX(&"Throw1")
	var total_value: int = 0 # 累计已创建的实际价值，包括成长加值和额外小阳光。
	for _index: int in range(num_create_sun): # 普通生产份数不被单份价值加成放大。
		total_value += _spawn_sun_value(sun_value + _production_growth_bonus)
	var extra: int = randi_range(extra_small_sun_min, extra_small_sun_max) # 本轮额外小阳光份数。
	for _index: int in range(extra): # 额外小阳光也属于本株实际生产。
		total_value += _spawn_sun_value(15)
	advance_production_growth_bonus()
	if total_value > 0:
		production_created.emit(total_value)

## 当前生产完成后累加下轮单份价值；返回受上限约束的新加值。
func advance_production_growth_bonus() -> int:
	if production_growth_step > 0 and production_growth_cap > 0:
		_production_growth_bonus = mini(production_growth_cap,
			_production_growth_bonus + production_growth_step)
	return _production_growth_bonus

## [param value] 为额外奖励价值；允许同步死亡回调发放，不计入正常生产事件。
func spawn_specific_sun(value: int) -> void:
	if value <= 0 or not _can_spawn_sun(true):
		return
	SoundManager.play_character_SFX(&"Throw1")
	_spawn_sun_value(value)

## 将 [param total_value] 精确拆成不大于 [param max_piece_value] 的奖励阳光，只播放一次音效。
## 两参数必须为正；默认每份最多五十，避免高额储蓄生成遮挡棋盘的巨大阳光，且不发生产事件。
func spawn_specific_sun_batch(total_value: int, max_piece_value: int = 50) -> void:
	if total_value <= 0 or max_piece_value <= 0 or not _can_spawn_sun(true):
		return
	SoundManager.play_character_SFX(&"Throw1")
	var remaining: int = total_value # 尚未发放的精确总值，最后一份保留不足整份的余数。
	while remaining > 0:
		var piece: int = mini(remaining, max_piece_value) # 本份合法价值，不放大原版阳光比例。
		if _spawn_sun_value(piece) <= 0:
			return
		remaining -= piece

## [param allow_dead] 只为同步奖励允许本株已经死亡；排队释放、预览和跨场景回调一律拒绝。
func _can_spawn_sun(allow_dead: bool) -> bool:
	var game: MainGameManager = Global.main_game # 必须仍属于实际产出发生的当前战场。
	var character: Character000Base = owner as Character000Base # 场景所有者决定真实生命周期。
	return is_inside_tree() and not is_queued_for_deletion() \
			and is_instance_valid(character) and not character.is_queued_for_deletion() \
			and character.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
			and (allow_dead or not character.is_death) \
			and is_instance_valid(game) and game.is_inside_tree() and not game.is_queued_for_deletion() \
			and game.get_tree().current_scene == game and game.is_ancestor_of(self) \
			and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
			and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
			and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false) \
			and is_instance_valid(game.suns) and game.suns.is_inside_tree() \
			and not game.suns.is_queued_for_deletion() and game.is_ancestor_of(game.suns) \
			and is_instance_valid(marker_2d_create_sun) and marker_2d_create_sun.is_inside_tree()

## 创建 [param value] 价值的真实阳光并返回该值，失败返回零；产出和奖励共用本株材质。
func _spawn_sun_value(value: int) -> int:
	if value <= 0 or not _can_spawn_sun(true):
		return 0
	var new_sun: Sun = SceneRegistry.SUN.instantiate() # 每份阳光独立收集、存在计时和下落。
	new_sun.init_sun(value, Global.main_game.suns.to_local(marker_2d_create_sun.global_position),
		sun_visual_material)
	Global.main_game.suns.add_child(new_sun)
	var tween: Tween = new_sun.create_tween() # 从植株抛出后下落的竖直轨迹。
	tween.tween_property(new_sun, "position:y", -15.0, 0.3).as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(new_sun, "position:y", 45.0, 0.6).as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	new_sun.spawn_sun_tween = get_tree().create_tween()
	new_sun.spawn_sun_tween.set_parallel()
	new_sun.spawn_sun_tween.tween_subtween(tween)
	new_sun.spawn_sun_tween.tween_property(new_sun, "position:x", randf_range(-30, 30), 0.9).as_relative()
	new_sun.spawn_sun_tween.finished.connect(new_sun.on_sun_tween_finished)
	return new_sun.sun_value

## 创建原版先发光、后产出、再恢复的动画；实际产出时再次检查死亡和退场。
func create_sun() -> void:
	if not _can_spawn_sun(false) or not is_enabling:
		return
	var tween: Tween = create_tween() # 绑定本组件的发光流程，随本株释放自动终止。
	tween.tween_method(_update_sun_glow, Color(1, 1, 1), Color(2, 2, 2), 0.5)
	tween.tween_callback(_spawn_sun)
	tween.tween_method(_update_sun_glow, Color(2, 2, 2), Color(1, 1, 1), 0.5)

## [param value] 为本帧生产发光颜色，沿用身体组件的独立颜色来源。
func _update_sun_glow(value: Color) -> void:
	body.set_other_color(BodyCharacter.E_ChangeColors.CreateSunColor, value)

## 原版生产计时到期后开始发光并安排下一轮。
func _on_create_sun_timer_timeout() -> void:
	create_sun()
	change_production_interval()

## [param new_sun_value] 为下一轮普通阳光基础价值，不覆盖已积累的单份成长加值。
func change_sun_value(new_sun_value: int) -> void:
	sun_value = new_sun_value
