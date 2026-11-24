## 半血分裂时的三次近景。该节点独占时停、镜头、输入和音乐，退出走同一归还路径。
extends Node

## 主战斗镜头的临时取景与准确归还。
const CameraShot = preload("res://scripts/character/zombie_boss/savior/savior_cinematic_camera.gd")
## 原画的祈祷、停姿和传送材质。
const SaviorVisual = preload("res://scripts/character/zombie_boss/savior/savior_visual.gd")
## 显形、钟声与退场特效使用同一口钟和原图。
const Teleport = preload("res://scripts/fx/savior_teleport.gd")
## 切入特写时黑幕尚须在时停中按真实秒完成。
const BlackFlash = preload("res://scripts/fx/savior_black_flash.gd")
## 近景镜头的缓入缓出时长，按未缩放秒计。
const PORTRAIT_SECONDS := 0.89
## 每次移到下一位之前，给完全抬起的双掌留一拍。
const POSE_SECONDS := 0.28
## 合演前的回归镜头时长，按未缩放秒计。
const RETURN_SECONDS := 1.02

## 在按演员顺序播放的近景与回归镜头之间切换。
enum Stage { CLOSED, PORTRAIT, RETURN }

## 回归完成前本序列持有画面和输入。
var active: bool:
	get:
		return _stage != Stage.CLOSED
## 本次借用的战斗镜头及其原始机位。
var _shot := CameraShot.new()
## 当前特写或回归，从零累计实际秒。
var _stage := Stage.CLOSED
## 当前镜头已播放的真实时间。
var _elapsed := 0.0
## 时停期间仍继续演奏的背景音乐，结束后归还处理模式。
var _music_mode: Node.ProcessMode
## 特写依次扫过的成员索引。
var _portrait_index := 0
## 本次特写已启动自己的半速祈祷。
var _portrait_praying := false
## 达到最高抬掌的累计停留秒数。
var _held_seconds := 0.0
## 按正式队形依次拍摄的存活成员；离场时只释放本节点持有的引用。
var _members: Array[ZB000Base] = []
## 本场传送生产实际显形及共用钟声。
var _teleport: Teleport

## 普通战斗中的输入继续交给场景；取得暂停时再拦截。
func _ready() -> void:
	set_process_input(false)

## 在黑场中隐藏 [param members] 并取得 [param camera]。[param teleport] 和 [param set_light] 分别控制白光和原有红灯。
func begin(members: Array[ZB000Base], camera: MainGameCamera, teleport: Teleport, set_light: Callable) -> void:
	_members = members
	_teleport = teleport
	for member: ZB000Base in _members: # 真身与分身按提交后的队形依次显现。
		var pose := member.get_node(^"Body/SaviorVisual") as SaviorVisual # 使用即将进入特写的真实原画。
		pose.cancel_prayer()
		pose.set_teleport_pose(0.0)
		set_light.call(member, 0.0)
	_shot.borrow(camera)
	_music_mode = SoundManager.bgm_play.process_mode
	SoundManager.bgm_play.process_mode = Node.PROCESS_MODE_ALWAYS
	_teleport.set_cinematic_audio(true)
	_stage = Stage.PORTRAIT
	set_process_input(true)
	TreePauseManager.start_tree_pause(TreePauseManager.E_PauseFactor.SaviorCinematic)
	if active: # 暂停通知可以同步取消这次仪式。
		_focus(0)

## 用 [param delta] 的未缩放时长推进实际镜头，借助 [param flash] 和 [param reproject] 刷新冻结画面。返回是否已归还控制。
func advance(delta: float, flash: BlackFlash, reproject: Callable) -> bool:
	var step: float = delta / maxf(0.01, Engine.time_scale) # 倍速只影响正常战斗，镜头仍按真实秒。
	_elapsed += step
	if _stage == Stage.PORTRAIT:
		_show_portrait(step)
	elif _stage == Stage.RETURN:
		_shot.move(_elapsed / RETURN_SECONDS)
		if _elapsed >= RETURN_SECONDS:
			release()
	if active:
		flash.advance(step, step)
		reproject.call()
	return not active

## 从当下画面起步，接近第 [param index] 位真实演员。
func _focus(index: int) -> void:
	_portrait_index = index
	_portrait_praying = false
	_held_seconds = 0.0
	_shot.aim_at(_members[index], get_viewport().get_visible_rect().size)
	_stage = Stage.PORTRAIT
	_elapsed = 0.0

## 用 [param step] 推进正在聚焦的成员。先移动镜头，在缓入近景时出现光照与手势。
func _show_portrait(step: float) -> void:
	var actor: ZB000Base = _members[_portrait_index] # 当前镜头唯一尚未点亮的角色。
	var pose := actor.get_node(^"Body/SaviorVisual") as SaviorVisual # 保留原画动作的实际帧进度。
	_shot.move(_elapsed / PORTRAIT_SECONDS)
	_teleport.arrive(actor, clampf(inverse_lerp(0.23, 1.0, _elapsed), 0.0, 1.0), true)
	if not _portrait_praying and _elapsed >= 0.42:
		_portrait_praying = pose.stage_prayer(0.5 / maxf(0.01, Engine.time_scale), true)
	if not pose.is_ritual_pose_held():
		return
	if _held_seconds == 0.0:
		_teleport.ring_bell()
	_held_seconds += step
	if _held_seconds < POSE_SECONDS:
		return
	if _portrait_index + 1 < _members.size():
		_focus(_portrait_index + 1)
	else:
		_shot.aim_home()
		_stage = Stage.RETURN
		_elapsed = 0.0

## 本节点取得暂停才阻挡 [param _event]；其他暂停因素继续由项目自身处理。
func _input(_event: InputEvent) -> void:
	if active:
		get_viewport().set_input_as_handled()

## 正常回归、战斗结束和节点退出都完整归还镜头、时间、钟声与音乐。
func release() -> void:
	if not active:
		return
	_shot.restore()
	_stage = Stage.CLOSED
	_members = []
	set_process_input(false)
	TreePauseManager.end_tree_pause(TreePauseManager.E_PauseFactor.SaviorCinematic)
	if is_instance_valid(_teleport):
		_teleport.set_cinematic_audio(false)
	if is_instance_valid(SoundManager.bgm_play):
		SoundManager.bgm_play.process_mode = _music_mode

## 独立回收本节点所持有的暂停以及临时场景属性。
func _exit_tree() -> void:
	release()
