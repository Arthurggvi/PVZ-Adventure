## 同一战场所有救主共用的行动时钟与场景表现。教堂可接入自己的光场和亡影。
extends CanvasLayer
class_name SaviorBattle

## 时停更新镜头后请环境重新投影。
signal frozen_frame_requested
## 战斗结束后仍有余光撤回时，请环境刷新最后一帧。
signal final_lights_changed

## 场景按召唤需要惰性实例化，常规关卡开场不用加载。
const SCENE_PATH := "res://scenes/fx/savior_battle.tscn"
## 读取教堂现成的投影源，普通场地可以只播放技能本身。
const LightField = preload("res://scripts/battle/environment/battle_visibility_light_field.gd")
## 路灯花覆盖的同一份灯罩标定。
const LightSources = preload("res://scripts/adventure/zombie_church_light_sources.gd")
## 植物亡影只由支持该玩法的战场提供。
const PlantRemains = preload("res://scripts/adventure/zombie_church_plant_remains.gd")
## 活体路灯花的光照快照。
const Light = preload("res://scripts/battle/environment/battle_light_source.gd")
## 一场只运行一个行动树。
const ActionTree = preload("res://scripts/character/zombie_boss/savior/savior_action_tree.gd")
## 每个施法者的长时演出记录。
const SpellChannels = preload("res://scripts/adventure/savior_spell_channels.gd")
## 覆盖 HUD 的黑闪。
const BlackFlash = preload("res://scripts/fx/savior_black_flash.gd")
## 原画和传送钟声跟随同一时钟。
const Teleport = preload("res://scripts/fx/savior_teleport.gd")
## 入场与分裂镜头的导演。
const Cinematic = preload("res://scripts/character/zombie_boss/savior/savior_cinematic.gd")
## 物理步负责入场十字的连续接触。
const CrossAttack = preload("res://scripts/character/zombie_boss/savior/savior_entry_cross_attack.gd")
## 世界的十字柱表现。
const EntryCross = preload("res://scripts/fx/savior_entry_cross.gd")
## 福音柱和湮灭。
const Gospel = preload("res://scripts/fx/savior_gospel_effects.gd")

## 当前战斗拥有这组节点。
var _battle: MainGameManager
## 教堂以外可为空，临时柱体与命中仍照常运行。
var _field: LightField
## 教堂以外没有可复生的亡影。
var _remains: PlantRemains
## 安乐短黑闪需要实际流逝时间，暂停后重新起算。
var _last_ticks: int

## 统一推进同组所有角色。
var savior_actions := ActionTree.new()
## 按施法者隔离着地效果的数据。
var savior_channels := SpellChannels.new()
## 实际祈祷、分裂和特写。
@onready var savior_cinematic: Cinematic = $SaviorCinematic
## 入场与离场共用的光幕和音轨。
@onready var savior_teleport: Teleport = $SaviorTeleport
## 所有演员共用的全屏黑幕。
@onready var savior_flash: BlackFlash = $SaviorBlackout/Flash
## 信徒复生的余烬。
@onready var savior_effects: Node2D = $SaviorSkillEffects
## 入场和分裂共用的物理攻击。
var savior_entry_cross := CrossAttack.new()
## 在相机更新后提交十字的真实接触点。
@onready var _cross_view: EntryCross = $SaviorEntryCross
## 单个战场中的可受击福音白柱。
@onready var savior_gospel: Gospel = $SaviorGospel

## 取得 [param battle] 已有的救主场景，或为手动召唤创建唯一一份。
static func for_battle(battle: MainGameManager) -> SaviorBattle:
	var existing := battle.get_node_or_null(^"SaviorBattle") as SaviorBattle # 教堂场景已在入树时挂载。
	if existing != null:
		return existing
	var scene := load(SCENE_PATH) as PackedScene # 当实际生成为出战角色时才取演出资源。
	var arena := scene.instantiate() as SaviorBattle # 普通战场也使用同一套演员和判定。
	battle.add_child(arena)
	arena.configure(battle)
	return arena

## [param battle] 提供棋盘与时钟。可选 [param field]、[param remains] 接入当前地图环境。
func configure(battle: MainGameManager, field: LightField = null, remains: PlantRemains = null) -> void:
	_battle = battle
	_field = field
	_remains = remains
	if field == null:
		layer = 8 # 常规战场上方、原版卡槽下方。
	_last_ticks = Time.get_ticks_usec()
	savior_effects.configure(battle)
	savior_gospel.configure(battle, field)
	savior_channels.configure(battle, field, $Ground, $SpellTrack)
	savior_entry_cross.configure(battle.board)
	_cross_view.configure(battle, field, savior_entry_cross)
	savior_cinematic.configure(battle, self)
	savior_actions.configure(savior_flash)
	savior_teleport.configure(battle, field, set_savior_light)
	EventBus.subscribe("main_game_progress_update", _on_game_progress)

## 返回本次结算使用的活体路灯花覆盖，普通战场复用相同衰减。
func plantern_lights() -> Array[Light]:
	if is_instance_valid(_field):
		return _field.warm_lights(true)
	return LightSources.sample_plantern_lights(_battle.board)

## [param boss] 存活期间保留该战场实际存在的亡影。
func hold_plant_remains(boss: ZB000Base) -> void:
	if is_instance_valid(_remains):
		_remains.hold_cleansing(boss)

## 返回当前战场是否有可复生为信徒的植物亡影。
func has_revivable_plant_remains() -> bool:
	return is_instance_valid(_remains) and _remains.has_revivable_remains()

## 通过 [param spawn_follower] 处理支持亡影的地块。
func revive_plant_remains(spawn_follower: Callable) -> void:
	if is_instance_valid(_remains):
		_remains.revive(spawn_follower)

## [param actor] 的红灯随 [param strength] 交接到传送白光。
func set_savior_light(actor: ZB000Base, strength: float) -> void:
	var anchor := actor.get_node_or_null(^"Body/ChurchLight") as Marker2D # 锚点本身不承担战斗判定。
	if anchor == null:
		return
	anchor.visible = strength > 0.0
	if is_instance_valid(_field):
		_field.set_light_intensity(anchor.get_instance_id(), LightField.Tone.RED, strength)

## 时停只更新表现和画布投影，战斗时钟仍冻结。
func present_frozen_ritual() -> void:
	savior_channels.present(0.0)
	_cross_view.present_frame()
	savior_gospel.present_frame(0.0)
	savior_teleport.present_frame(0.0)
	savior_effects.queue_redraw()
	frozen_frame_requested.emit()

## [param delta] 是本局未暂停的战斗秒。
func _physics_process(delta: float) -> void:
	if is_instance_valid(_battle) and _battle.zombie_manager.is_game_running():
		savior_channels.advance_ground(delta)
		savior_actions.advance(delta)
		savior_entry_cross.advance(delta)

## [param delta] 推进正常演出，环境渲染在本步骤之后读取光源。
func _process(delta: float) -> void:
	if not is_instance_valid(_battle):
		return
	var now: int = Time.get_ticks_usec() # 安乐走未缩放的演出时钟。
	var seconds: float = (now - _last_ticks) * 0.000001
	_last_ticks = now
	if not _battle.zombie_manager.is_game_running():
		savior_flash.stop()
		if savior_teleport.present_frame(delta):
			final_lights_changed.emit()
		return
	savior_flash.advance(delta, seconds)
	if get_tree().paused:
		return # 分裂的落黑回调可以在这一帧取得时停。
	savior_channels.present(delta)
	_cross_view.present_frame()
	savior_gospel.present_frame(delta)
	savior_teleport.present_frame(delta)

## [param what] 为暂停通知，恢复时不补计暂停期间的真实时间。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		_last_ticks = Time.get_ticks_usec()

## [param progress] 离开战斗时归还镜头、时停和技能光源。
func _on_game_progress(progress: MainGameManager.E_MainGameProgress) -> void:
	if progress == MainGameManager.E_MainGameProgress.MAIN_GAME or Global.main_game != _battle:
		return
	savior_cinematic.cancel()
	savior_entry_cross.clear()
	savior_channels.clear()
	savior_effects.clear()
	savior_gospel.clear()
	final_lights_changed.emit()

## 场景转换后不再处理全局战斗通知。
func _exit_tree() -> void:
	if _battle != null:
		EventBus.unsubscribe("main_game_progress_update", _on_game_progress)
