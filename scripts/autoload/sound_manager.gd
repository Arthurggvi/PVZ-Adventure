extends Node
class_name SoundManagerClass

enum Bus {MASTER, BGM, SFX}

## 音效语义通道；UI 和警告旁路远近空间分流，场景可在 SFX 总线上统一处理，音乐保持独立。
enum SFXSpace {COMBAT, DISTANT, UI}
## 当前场景对音效路由的弱所有权，离场不延长场景生命周期。
var _environment_owner: WeakRef
## 由场景提供的近战与远处通道，不缓存环境资源。
var _environment_routes: Dictionary = {}
## 操作、奖励和警告走基础 SFX；是否附加统一环境滤镜由当前场景决定。
const CLEAR_FEEDBACK: Array[StringName] = [
	&"gravebutton", &"bleep", &"tap", &"buttonclick", &"pause", &"points", &"coin", &"diamond",
	&"chime", &"moneyfalls", &"buzzer", &"seedlift", &"shovel", &"tap2", &"siren", &"awooga", &"finalwave",
	&"hugewave", &"losemusic", &"readysetplant", &"scream", &"winmusic", &"plant1", &"plant2", &"plant_water",
]
## 远方叫声采用较深低通；啃食、命中和投掷保留近战瞬态。
const DISTANT_VOICES: Array[StringName] = [
	&"SquashHmm", &"Rarrgh", &"Dancer", &"zamboni", &"dolphin_appears", &"jackinthebox",
	&"bungee_scream", &"gargantudeath", &"imp", &"bossexplosion",
]

## [param owner] 租用本场的 [param combat] 和 [param distant] 总线；不改 SFX、BGM 或 Master 的效果。
func set_environment_routes(owner: Node, combat: StringName, distant: StringName) -> void:
	_environment_owner = weakref(owner)
	_environment_routes = {SFXSpace.COMBAT: combat, SFXSpace.DISTANT: distant}
	for player: AudioStreamPlayer in sfx_bullet_pool: # 跨阶段仍在播放的短音效也平滑进入介质。
		player.bus = spatial_sfx_bus(player.get_meta("sfx_space", SFXSpace.COMBAT))
	for player: AudioStreamPlayer in [rain_player, storm_rain_player, boss_phase_roar_player]: # 全局专用环境播放器仍服从同一音效音量。
		player.bus = spatial_sfx_bus(SFXSpace.DISTANT)

## [param owner] 只能撤销自己的路由；先还原播放器，再由场景删除临时总线。
func clear_environment_routes(owner: Node) -> void:
	if _environment_owner == null or _environment_owner.get_ref() != owner:
		return
	_environment_owner = null
	_environment_routes.clear()
	for player: AudioStreamPlayer in sfx_bullet_pool: # 池复用前恢复正式 SFX，避免关卡退出后残留湿声。
		player.bus = &"SFX"
	for player: AudioStreamPlayer in [rain_player, storm_rain_player, boss_phase_roar_player]: # 专用播放器与池使用同一回收时机。
		player.bus = &"SFX"

## 返回 [param space] 对应的可用总线；无环境或场景已销毁时退回原版 SFX。
func spatial_sfx_bus(space: SFXSpace = SFXSpace.COMBAT) -> StringName:
	if space == SFXSpace.UI or _environment_owner == null or _environment_owner.get_ref() == null:
		return &"SFX"
	var route: StringName = _environment_routes.get(space, &"SFX") # 按名字查询，允许其他场景创建自己的总线。
	return route if AudioServer.get_bus_index(route) >= 0 else &"SFX"

@onready var bgm_play: AudioStreamPlayer = $BGMPlay
@onready var sfx_all: Node = $SFXAll
@onready var crazy_dave_player: AudioStreamPlayer = $SFXAll/CrazyDavePlayer
## 原版雨声底层，沿用 SFX 总线与音量设置。
@onready var rain_player: AudioStreamPlayer = $SFXAll/RainPlayer
## 暴雨补充层，与原版雨声独立循环并按雨势混入。
@onready var storm_rain_player: AudioStreamPlayer = $SFXAll/StormRainPlayer
## Boss 阶段咆哮播放器，独立于短音效的重复播放过滤。
@onready var boss_phase_roar_player: AudioStreamPlayer = $SFXAll/BossPhaseRoar

## 当前帧播放的音效(每隔25物理帧清除一次)
## 音效每25物理帧内不可以重复播放
## 音效资源只在首次真实播放时解析，启动不提前加载全量候选。
var _stream_cache: Dictionary[String, AudioStream] = {}
## 短音效热缓存只保留有限个最近使用的流；播放中的播放器独立持有。
const SFX_CACHE_MAX_ENTRIES := 48
## 以导入流的实际音频数据字节估算缓存预算，长音效不会挤满整个缓存。
const SFX_CACHE_MAX_BYTES := 8 * 1024 * 1024
## 每条缓存记录的估算字节数及合计。
var _stream_bytes: Dictionary[String, int] = {}
var _stream_cache_bytes: int = 0

## [param path] 为音效路径；统一缓存流资源，解析失败返回 null。
func _stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		var cached: AudioStream = _stream_cache[path] # 字典插入顺序维护 LRU。
		_stream_cache.erase(path)
		_stream_cache[path] = cached
		return cached
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		push_error("SoundManager: invalid SFX resource " + path)
		return null
	var bytes: int = _estimate_stream_bytes(stream) # 音频数据大小，不代表整个引擎内存。
	if bytes > SFX_CACHE_MAX_BYTES:
		return stream
	while not _stream_cache.is_empty() and (_stream_cache.size() >= SFX_CACHE_MAX_ENTRIES or _stream_cache_bytes + bytes > SFX_CACHE_MAX_BYTES):
		var oldest: String = _stream_cache.keys()[0] # 最久未使用的流。
		_stream_cache_bytes -= _stream_bytes[oldest]
		_stream_bytes.erase(oldest)
		_stream_cache.erase(oldest)
	_stream_cache[path] = stream
	_stream_bytes[path] = bytes
	_stream_cache_bytes += bytes
	return stream

## [param stream] 为原生音频流；按数据格式估算，未知格式按 PCM 上界预算。
func _estimate_stream_bytes(stream: AudioStream) -> int:
	if stream is AudioStreamWAV or stream is AudioStreamMP3:
		return stream.data.size()
	# Ogg 等不读取整包序列化数据，保守按双声道 48kHz 16bit PCM 时长计费。
	return maxi(1, ceili(stream.get_length() * 48000.0 * 4.0))

## [param value] 可以是单一音轨或候选数组，随机结果仍使用同一缓存。
func _select_stream(value: Variant) -> AudioStream:
	if value is Array:
		if value.is_empty():
			return null
		value = value.pick_random()
	if value is AudioStream:
		return value
	return _stream(value) if value is String else null

var curr_frame_sfx:Array[AudioStream] = []
var frame_num:=0
## 高能重击需要的安静间隔，单位为真实毫秒，覆盖多个脉冲可能同时起播的音频缓冲。
const THREEPEATER_LASER_ACCENT_GAP_MS: int = 110
## 上一次高能脉冲发声的渲染帧，同帧多束和多株合并为一声。
var _last_threepeater_laser_frame: int = -1
## 上一次高能音效的请求时刻；初始值允许首发以完整重音播放。
var _last_threepeater_laser_ms: int = -THREEPEATER_LASER_ACCENT_GAP_MS

#func _ready() -> void:
	#Global.config_service.load_and_apply_config()
	#Global.save_config()

@warning_ignore("unused_parameter")
func _physics_process(delta: float) -> void:
	frame_num = wrapi(frame_num + 1, 0, 25)
	if frame_num == 0:
		curr_frame_sfx.clear()

#region 播放音乐和音效
func play_bgm(stream: AudioStream):
	bgm_play.stream = stream
	bgm_play.play()

## 播放 [param stream] 指定的背景音乐；相同曲目正在播放时保持进度，避免从头重播。
func play_bgm_if_changed(stream: AudioStream) -> void:
	if bgm_play.stream == stream and bgm_play.playing:
		return
	play_bgm(stream)

## 菜单与地图共用城镇曲目和现有 BGM 总线；同一曲目保持播放位置。
func play_town_bgm() -> void:
	# ResourceLoader 缓存保证两场景取得同一个流；循环参数不影响播放器或音量设置。
	var town := load("res://assets/adventure/audio/mus_town.wav") as AudioStreamWAV
	town.loop_mode = AudioStreamWAV.LOOP_FORWARD
	town.loop_begin = 0
	town.loop_end = int(town.get_length() * town.mix_rate)
	play_bgm_if_changed(town)

#region 植物和僵尸有关音效(植物、僵尸、子弹、受击)
"""
 音效分为 僵尸受击 子弹音效 角色(植物僵尸) 戴夫 和其他音效
"""

## 僵尸受击音效种类
enum TypeBeAttackSFX{
	Null,		## 无声音
	Plastic,	## 塑料
	Shield		## 铁器
}

## 僵尸受击音效资源字典
const SFXBeAttackMap := {
	TypeBeAttackSFX.Null: null,
	TypeBeAttackSFX.Plastic: [
		"res://assets/audio/SFX/bullet/plastichit.ogg",
		"res://assets/audio/SFX/bullet/plastichit2.ogg"
	],
	TypeBeAttackSFX.Shield: [
		"res://assets/audio/SFX/bullet/shieldhit1.ogg",
		"res://assets/audio/SFX/bullet/shieldhit2.ogg"
	],
}

## 子弹音效种类
enum TypeBulletSFX{
	Null,		## 无声音
	Pea,		## 豌豆
	PeaFire,	## 火焰豌豆
	Corn,		## 玉米粒
	Butter,		## 黄油
	Melon,		## 西瓜
	Bowling = 1001,		## 保龄球
}

## 子弹音效资源字典
const SFXBulletMap := {
	TypeBulletSFX.Null: null,
	TypeBulletSFX.Pea: [
		"res://assets/audio/SFX/bullet/splat1.ogg",
		"res://assets/audio/SFX/bullet/splat2.ogg",
		"res://assets/audio/SFX/bullet/splat3.ogg"
	],
	TypeBulletSFX.PeaFire: [
		"res://assets/audio/SFX/bullet/firepea.ogg",
	],
	TypeBulletSFX.Corn:[
		"res://assets/audio/SFX/bullet/kernelpult2.ogg",
		"res://assets/audio/SFX/bullet/kernelpult.ogg"
	],
	TypeBulletSFX.Butter:[
		"res://assets/audio/SFX/bullet/butter.ogg"
	],
	TypeBulletSFX.Melon:[
		"res://assets/audio/SFX/bullet/melonimpact.ogg",
		"res://assets/audio/SFX/bullet/melonimpact2.ogg"
	],

	TypeBulletSFX.Bowling: [
		"res://assets/audio/SFX/bullet/bowlingimpact.ogg",
		"res://assets/audio/SFX/bullet/bowlingimpact2.ogg",
	],

}

## 植物\僵尸音效字典
const SFXCharacterMap := {
	## -------------------------------植物-------------------------------
	## 豌豆射手发射字典
	&"Throw":[
		"res://assets/audio/SFX/plant/throw1.ogg",
		"res://assets/audio/SFX/plant/throw2.ogg"
	],
	## 向日葵发射阳光
	&"Throw1":"res://assets/audio/SFX/plant/throw1.ogg",
	## 樱桃炸弹爆炸
	&"CherryBomb":"res://assets/audio/SFX/plant/cherrybomb.ogg",
	## 转基因玉米炮的落地爆裂和低频余震，首次命中才加载。
	&"CornCobImpact": "res://resources/audio/sfx/corn_cob_impact.wav",
	## 土豆雷爆炸
	&"PotatoMine": "res://assets/audio/SFX/plant/potato_mine.ogg",
	## 大嘴花
	&"BigChomp": "res://assets/audio/SFX/plant/bigchomp.ogg",
	## 小喷菇发射子弹
	&"Puff": "res://assets/audio/SFX/plant/puff.ogg",
	## 阳光菇长大
	&"PlantGrow": "res://assets/audio/SFX/plant/plantgrow.ogg",
	## 大喷菇发射子弹
	&"Fume": "res://assets/audio/SFX/plant/fume.ogg",
	## 三线射手高能开火的短激光脉冲。
	&"ThreePeaterLaser": "res://resources/audio/sfx/threepeater_high_energy.wav",
	## 墓碑吞噬者
	&"GraveBusterChomp":"res://assets/audio/SFX/plant/gravebusterchomp.ogg",
	## 魅惑菇
	&"MindControlled": "res://assets/audio/SFX/plant/mindcontrolled.ogg",
	## 寒冰菇
	&"Frozen": "res://assets/audio/SFX/plant/frozen.ogg",
	## 毁灭菇
	&"DoomShroom": "res://assets/audio/SFX/plant/doomshroom.ogg",
	## 倭瓜发现敌人
	&"SquashHmm":[
		"res://assets/audio/SFX/plant/squash_hmm2.ogg",
		"res://assets/audio/SFX/plant/squash_hmm.ogg"
	],
	## 火爆辣椒
	&"Jalapeno": "res://assets/audio/SFX/plant/jalapeno.ogg",
	## 三叶草
	&"blover": "res://assets/audio/SFX/plant/blover.ogg",
	## 磁力菇
	&"magnetshroom": "res://assets/audio/SFX/plant/magnetshroom.ogg",
	## 磁力菇
	&"coblaunch": "res://assets/audio/SFX/plant/coblaunch.ogg",




	## -------------------------------僵尸-------------------------------
	## 通用音效
	## 掉头
	&"limbs_pop": "res://assets/audio/SFX/zombie/limbs_pop.ogg",

	## 啃食
	&"Chomp":[
		"res://assets/audio/SFX/zombie/chomp.ogg",
		"res://assets/audio/SFX/zombie/chomp2.ogg",
		"res://assets/audio/SFX/zombie/chompsoft.ogg"
	],
	## 掉头
	&"Shoop":"res://assets/audio/SFX/zombie/shoop.ogg",
	## 啃食大蒜
	&"yuck":[
		"res://assets/audio/SFX/zombie/yuck2.ogg",
		"res://assets/audio/SFX/zombie/yuck.ogg"
	],
	## 撑杆跳
	&"Polevault":"res://assets/audio/SFX/zombie/polevault.ogg",
	## 滑雪僵尸借冰起跳的短掠雪声。
	&"SkiTakeoff": "res://assets/adventure/zombies/ski/takeoff.ogg",
	## 读报僵尸愤怒
	&"Rarrgh":[
		"res://assets/audio/SFX/zombie/newspaper_rarrgh.ogg",
		"res://assets/audio/SFX/zombie/newspaper_rarrgh2.ogg"
	],
	## 读报僵尸报纸掉落
	&"Rip":	"res://assets/audio/SFX/zombie/newspaper_rip.ogg",
	## 舞王入场
	&"Dancer":"res://assets/audio/SFX/zombie/dancer.ogg",
	## 冰车僵尸入场
	&"zamboni":"res://assets/audio/SFX/zombie/zamboni.ogg",
	## 冰车僵尸爆炸\小丑僵尸爆炸
	&"explosion":"res://assets/audio/SFX/zombie/explosion.ogg",
	## 海豚僵尸入场
	&"dolphin_appears":"res://assets/audio/SFX/zombie/dolphin_appears.ogg",
	## 海豚僵尸跳跃
	&"dolphin_before_jumping":"res://assets/audio/SFX/zombie/dolphin_before_jumping.ogg",
	## 小丑僵尸入场
	&"jackinthebox":"res://assets/audio/SFX/zombie/jackinthebox.ogg",
	## 小丑僵尸爆炸惊讶
	&"jack_suprise":[
		"res://assets/audio/SFX/zombie/jack_surprise.ogg",
		"res://assets/audio/SFX/zombie/jack_surprise2.ogg",
	],
	## 小丑僵尸盒子打开
	&"boing":"res://assets/audio/SFX/zombie/boing.ogg",
	## 气球僵尸入场
	&"ballooninflate":"res://assets/audio/SFX/zombie/ballooninflate.ogg",
	## 气球爆炸
	&"balloon_pop":"res://assets/audio/SFX/zombie/balloon_pop.ogg",
	## 矿工僵尸绝地
	&"digger_zombie": "res://assets/audio/SFX/zombie/digger_zombie.ogg",
	## 跳跳僵尸跳跃
	&"pogo_zombie": "res://assets/audio/SFX/zombie/pogo_zombie.ogg",
	## 蹦极僵尸入场
	&"bungee_scream":[
		"res://assets/audio/SFX/zombie/bungee_scream.ogg",
		"res://assets/audio/SFX/zombie/bungee_scream2.ogg",
		"res://assets/audio/SFX/zombie/bungee_scream3.ogg"
	],
	## 扶梯僵尸放置梯子
	&"ladder_zombie": "res://assets/audio/SFX/zombie/ladder_zombie.ogg",
	## 篮球僵尸发射篮球子弹
	&"basketball": "res://assets/audio/SFX/zombie/basketball.ogg",
	## 僵王吐出冰火球。
	&"bossboulderattack": "res://assets/audio/SFX/zombie/bossboulderattack.ogg",
	## 僵王机甲死亡爆炸。
	&"bossexplosion": "res://assets/audio/SFX/zombie/bossexplosion.ogg",
	## 僵王低头、抬头的液压动作。
	&"hydraulic": "res://assets/audio/SFX/zombie/hydraulic.ogg",
	## 僵王放置僵尸及蹦极时的手臂动作。
	&"hydraulic_short": "res://assets/audio/SFX/zombie/hydraulic_short.ogg",
	## 僵王丢车时的投掷动作。
	&"RVthrow": "res://assets/audio/SFX/zombie/RVthrow.ogg",

	## 巨人僵尸攻击\倭瓜
	&"gargantuar_thump": "res://assets/audio/SFX/zombie/gargantuar_thump.ogg",
	## 巨人僵尸死亡
	&"gargantudeath": "res://assets/audio/SFX/zombie/gargantudeath.ogg",
	## 小鬼被抛射
	&"imp":[
		"res://assets/audio/SFX/zombie/imp.ogg",
		"res://assets/audio/SFX/zombie/imp2.ogg"
	]
}

## 戴夫音效字典
const SFXCarzyDaveMap := {
	## 一秒左右
	&"crazydaveshort" : [
		"res://assets/audio/SFX/carzy/crazydaveshort1.ogg",
		"res://assets/audio/SFX/carzy/crazydaveshort2.ogg",
		"res://assets/audio/SFX/carzy/crazydaveshort3.ogg"
	],
	## 两秒左右
	&"crazydavelong" : [
		"res://assets/audio/SFX/carzy/crazydavelong1.ogg",
		"res://assets/audio/SFX/carzy/crazydavelong2.ogg",
		"res://assets/audio/SFX/carzy/crazydavelong3.ogg"
	],
	## 三秒左右
	&"crazydaveextralong" : [
		"res://assets/audio/SFX/carzy/crazydaveextralong1.ogg",
		"res://assets/audio/SFX/carzy/crazydaveextralong2.ogg",
		"res://assets/audio/SFX/carzy/crazydaveextralong3.ogg"
	],
	&"crazydavecrazy" : [
		"res://assets/audio/SFX/carzy/crazydavecrazy.ogg"
	],
	&"crazydavescream" : [
		"res://assets/audio/SFX/carzy/crazydavescream2.ogg",
		"res://assets/audio/SFX/carzy/crazydavescream.ogg"
	],
}

## 音效对象池实现
var sfx_bullet_pool = []

## 用 SFX 对象池播放 [param sfx_resource]，并应用本次的 [param volume_db] 和 [param pitch_scale]。
## 默认同帧合并相同资源；[param deduplicate_in_frame] 为 false 时保留每次播放事件。
## [param space] 指定近战、远声或清晰反馈；每次取出播放器都重新路由，防止池复用串线。
## 返回实际使用的播放器，播放被合并时返回 null。
func play_sfx_with_pool(sfx_resource: AudioStream, volume_db: float = 0.0,
		pitch_scale: float = 1.0, deduplicate_in_frame: bool = true,
		space: SFXSpace = SFXSpace.COMBAT) -> AudioStreamPlayer:
	if deduplicate_in_frame:
		if sfx_resource in curr_frame_sfx:
			return null
		curr_frame_sfx.append(sfx_resource)

	var player: AudioStreamPlayer # 本次取得的闲置播放器，没有闲置实例时创建。
	# 从池中获取可用播放器
	for p: AudioStreamPlayer in sfx_bullet_pool: # 已挂在 SFX 总线上的池内实例。
		if not p.playing:
			player = p
			break

	# 如果没有可用播放器，创建新的
	if not player:
		player = AudioStreamPlayer.new()
		player.bus = AudioServer.get_bus_name(Bus.SFX)
		player.finished.connect(_on_sfx_finished.bind(player))
		sfx_all.add_child(player)
		sfx_bullet_pool.append(player)

	## 配置播放器
	player.set_meta("sfx_space", space)
	player.bus = spatial_sfx_bus(space)
	player.stream = sfx_resource
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return player

## [param player] 完成播放后释放流，但保留可复用播放器及其连接。
func _on_sfx_finished(player: AudioStreamPlayer):
	if is_instance_valid(player) and not player.playing:
		player.stream = null

## 播放僵尸受击音效
## [param type_bullet_zombie_sfx] 为被击中材质，[param source] 是接触点所属节点，[param point] 为实际世界触点。
func play_be_attack_SFX(type_bullet_zombie_sfx: TypeBeAttackSFX, source: Node = null, point: Vector2 = Vector2.INF) -> void:
	var selected: AudioStream = _select_stream(SFXBeAttackMap.get(type_bullet_zombie_sfx)) # 保留原素材选择语义。
	if selected != null:
		play_world_sfx(selected, source, point, 0.0, 1.0, &"hit")

## 播放 [param type_bullet_sfx]；[param source] 和 [param point] 来自当前弹体命中或落地点。
func play_bullet_attack_SFX(type_bullet_sfx: TypeBulletSFX, source: Node = null, point: Vector2 = Vector2.INF) -> void:
	var selected: AudioStream = _select_stream(SFXBulletMap.get(type_bullet_sfx)) # 每次命中只选一次原音色。
	if selected != null:
		play_world_sfx(selected, source, point, 0.0, 1.0, &"projectile_impact")

## [param source] 与 [param point] 提供 [param option] 的真实世界声源，[param priority] 供场景池保留关键冲击。
## 仅原音效池返回播放器，定位短声由当前关卡持有。
func play_character_SFX(option: StringName, source: Node = null, point: Vector2 = Vector2.INF,
		priority: int = 0) -> AudioStreamPlayer:
	var selected: AudioStream = _select_stream(SFXCharacterMap.get(option)) # 只抽取一次，沿用原战斗随机顺序。
	var space: SFXSpace = SFXSpace.DISTANT if option in DISTANT_VOICES else SFXSpace.COMBAT # 发声身份决定听觉距离，不改原音效资源。
	return play_world_sfx(selected, source, point, 0.0, 1.0, option, true, priority, space) if selected != null else null

## 返回 [param source] 所属战局显式启用的位置音效接收器。场外预览、UI 与未注入的战场返回空。
func world_audio_for(source: Node) -> Node:
	var game: MainGameManager = Global.main_game # 正式战斗当前所有者，音频服务不另存关卡全局标识。
	if not is_instance_valid(source) or not is_instance_valid(game) or not is_instance_valid(game.world_audio):
		return null
	return game.world_audio if source == game or game.is_ancestor_of(source) else null

## [param stream] 沿用原素材，以 [param source] 确定作用域。[param point] 默认取 Node2D 的视觉原点。
## [param volume_db]、[param pitch_scale] 与 [param deduplicate] 保留原音效参数。
## [param family] 和 [param priority] 供局内池分区合并与保留关键瞬态，[param space] 保持原总线语义。
## 只有回退到原播放器时才返回该播放器。接管路径只播放一份。
func play_world_sfx(stream: AudioStream, source: Node, point: Vector2 = Vector2.INF,
		volume_db: float = 0.0, pitch_scale: float = 1.0, family: StringName = &"combat",
		deduplicate: bool = true, priority: int = 0, space: SFXSpace = SFXSpace.COMBAT) -> AudioStreamPlayer:
	var router: Node = world_audio_for(source) # 每次只使用本场战斗授权的局内接收器。
	if router != null and router.is_node_ready() and space != SFXSpace.UI:
		var at: Vector2 = source.global_position if not point.is_finite() and source is Node2D else point # 事件坐标优先于节点原点。
		if at.is_finite():
			router.play_at(stream, at, volume_db, pitch_scale, family, 0.65 if space == SFXSpace.DISTANT else 0.0, priority)
			return null
	return play_sfx_with_pool(stream, volume_db, pitch_scale, deduplicate, space)

## 从 [param cue] 的真实挂点播放同一声音。[param family] 和 [param priority] 控制局内池的合并与保留。
## 支持空间池时归还旧播放器的职责；其它战场仍由原节点负责声像和生命周期。
func play_attached_sfx(cue: AudioStreamPlayer2D, family: StringName, priority: int = 0) -> void:
	var router: Node = world_audio_for(cue) # 仅当前显式注入的场景能接管此声源。
	if router != null and router.is_node_ready():
		router.play_at(cue.stream, cue.global_position, cue.volume_db, cue.pitch_scale, family, 0.0, priority)
	else:
		cue.bus = spatial_sfx_bus()
		cue.play()

## 高能每个可见的开火帧响一次。同帧齐射合声，后续脉冲继续沿用战斗总线与音效池。
## 密集跟发降低音量，保留单发重击并给同一音频缓冲内叠播的脉冲留出余量。
## [param source] 和 [param point] 提供实际弹口；空间池只合并相邻位置的声音。
func play_threepeater_laser_SFX(source: Node = null, point: Vector2 = Vector2.INF) -> void:
	var frame: int = Engine.get_process_frames() # 同一画面中的声音起点无需叠播。
	if frame == _last_threepeater_laser_frame and world_audio_for(source) == null:
		return
	_last_threepeater_laser_frame = frame
	var stream: AudioStream = _select_stream(SFXCharacterMap[&"ThreePeaterLaser"]) # 首次开火才载入。
	if stream != null:
		var now: int = Time.get_ticks_msec() # 与音频播放时钟同速，慢镜与倍速时仍按实际间隔混音。
		var following_quickly: bool = now - _last_threepeater_laser_ms < THREEPEATER_LASER_ACCENT_GAP_MS # 密集叠播时让出音量。
		_last_threepeater_laser_ms = now
		play_world_sfx(stream, source, point, -12.5 if following_quickly else -5.0, 1.0, &"laser", false)

## 从 [param source] 所属的战斗在 [param point] 播放玉米炮落地声。
## [param follows_recent] 表示前一炮的低频余震还在播放，给跟发降音量以免密集落炮时叠满总线。
func play_corn_cob_impact_SFX(source: Node, point: Vector2, follows_recent: bool) -> void:
	var stream: AudioStream = _select_stream(SFXCharacterMap[&"CornCobImpact"]) # 一次载入，首发和跟发共用。
	if stream != null:
		var gain_db: float = -11.0 if follows_recent else -2.0 # 保留首响余量，后续命中仍给出清楚的起音。
		play_world_sfx(stream, source, point, gain_db, 1.0, &"CornCobImpact", false, 2)

## 播放阶段龙咆哮，沿用战斗 SFX 总线与音量设置。
func play_boss_phase_roar() -> void:
	if boss_phase_roar_player.stream == null:
		boss_phase_roar_player.stream = _stream(
			"res://assets/audio/SFX/zombie/black_general_phase_transition_roar.ogg")
	if boss_phase_roar_player.stream != null:
		boss_phase_roar_player.play()


## 播放戴夫音效
func play_crazy_dave_SFX(option: StringName) -> void:
	var selected: AudioStream = _select_stream(SFXCarzyDaveMap.get(option))
	if selected == null:
		return
	crazy_dave_player.stream = selected
	crazy_dave_player.play()

## 启动原版雨声循环，使用独立流以保留原素材的导入设置。
func play_rain_SFX() -> void:
	if rain_player.stream == null:
		var rain_loop := load("res://assets/audio/sounds/rain.ogg").duplicate() as AudioStreamOggVorbis # 仅供雨景播放器使用的流。
		rain_loop.loop = true
		rain_player.stream = rain_loop
	rain_player.play()

## 应用天气提供的雨声混音，已在循环的音轨保留播放进度。
## [param gains] x 为原版雨声、y 为暴雨音轨的线性增益，0 时静音。
## [param storm_audio] 已开启循环的暴雨音轨；空值时释放暴雨层。
func set_rain_mix(gains: Vector2, storm_audio: AudioStream = null) -> void:
	rain_player.volume_db = linear_to_db(maxf(gains.x, 0.0001))
	if gains.x > 0.001 and not rain_player.playing:
		play_rain_SFX()

	if storm_rain_player.stream != storm_audio:
		storm_rain_player.stop()
		storm_rain_player.stream = storm_audio
	# 先设增益再启动，避免第一帧以默认音量播放。
	storm_rain_player.volume_db = linear_to_db(maxf(gains.y, 0.0001))
	if gains.y > 0.0 and storm_audio != null and not storm_rain_player.playing:
		storm_rain_player.play()

## 停止本场雨的两层循环并释放关卡提供的暴雨素材引用。
func stop_rain_SFX() -> void:
	rain_player.stop()
	rain_player.stream = null # 天气离场不保留独立复制的循环流。
	rain_player.volume_db = 0.0
	storm_rain_player.stop()
	storm_rain_player.stream = null
#endregion

#region 其余音效
const SFXOtherMap := {
	##-------------------------- 按钮相关 --------------------------
	## 开始菜单点击
	&"gravebutton": "res://assets/audio/SFX/button/gravebutton.ogg",
	## 鼠标进入开始菜单
	&"bleep":"res://assets/audio/SFX/button/bleep.ogg",
	##
	&"tap":"res://assets/audio/SFX/button/tap.ogg",
	## 选项按钮
	&"buttonclick":"res://assets/audio/SFX/button/buttonclick.ogg",
	## 暂停
	&"pause": "res://assets/audio/SFX/button/pause.ogg",
	## 点击阳光
	&"points": "res://assets/audio/SFX/button/points.ogg",
	## 拾取银币和金币。
	&"coin":"res://assets/audio/SFX/item/coin.ogg",
	## 金币首次落地。
	&"moneyfalls":"res://assets/audio/sounds/moneyfalls.ogg",
	## 拾取钻石。
	&"diamond":"res://resources/audio/sfx/diamond_pickup.wav",
	## 钻石或花园植物掉出。
	&"chime":"res://assets/audio/SFX/item/chime.ogg",
	##-------------------------- 卡片相关 --------------------------
	&"buzzer":"res://assets/audio/SFX/card_and_shovel/buzzer.ogg",
	&"seedlift":"res://assets/audio/SFX/card_and_shovel/seedlift.ogg",
	&"shovel":"res://assets/audio/SFX/card_and_shovel/shovel.ogg",
	&"tap2":"res://assets/audio/SFX/card_and_shovel/tap2.ogg",

	##-------------------------- 进度相关 --------------------------
	## 汽笛音效
	&"siren": "res://assets/audio/SFX/progress/siren.ogg",
	## TODO :这个也是汽笛音效？
	&"awooga":"res://assets/audio/SFX/progress/awooga.ogg",
	## 最后一波
	&"finalwave":"res://assets/audio/SFX/progress/finalwave.ogg",
	## 大波僵尸
	&"hugewave":"res://assets/audio/SFX/progress/hugewave.ogg",
	## 失败
	&"losemusic":"res://assets/audio/SFX/progress/losemusic.ogg",
	## 准备安放植物
	&"readysetplant":"res://assets/audio/SFX/progress/readysetplant.ogg",
	## 戴夫尖叫
	&"scream":"res://assets/audio/SFX/progress/scream.ogg",
	## 获胜音效
	&"winmusic":"res://assets/audio/SFX/progress/winmusic.ogg",


	##-------------------------- 主游戏场景物品相关 --------------------------
	## 墓碑生成
	&"gravestone_rumble":"res://assets/audio/SFX/zombie/gravestone_rumble.ogg",
	## 植物种植音效
	&"plant1": "res://assets/audio/SFX/plant_create/plant.ogg",
	## 植物铲除音效
	&"plant2":"res://assets/audio/SFX/plant_create/plant2.ogg",
	## 植物种植在水上
	&"plant_water": "res://assets/audio/SFX/plant_create/plant_water.ogg",
	## 缠绕水草抓住目标
	&"floop": "res://assets/audio/sounds/floop.ogg",
	## 僵尸入水音效、水花音效
	&"zombie_entering_water": "res://assets/audio/SFX/zombie/zombie_entering_water.ogg",
	## -------- 小推车 --------
	&"lawnmower": "res://assets/audio/SFX/item/lawnmower.ogg",
	&"pool_cleaner": "res://assets/audio/SFX/item/pool_cleaner.ogg",
	## -------- 锤子 --------
	&"swing": "res://assets/audio/SFX/item/swing.ogg",
	&"bonk": "res://assets/audio/SFX/item/bonk.ogg",
	## -------- 花园 -----------
	&"prize": "res://assets/audio/SFX/garden/prize.ogg",
	## -------- 僵尸出土 ------------
	&"dirt_rise": "res://assets/audio/SFX/zombie/dirt_rise.ogg",
	## --------- 花瓶破碎     -------------
	&"vase_breaking": "res://assets/audio/SFX/item/vase_breaking.ogg",


	##-------------------------- 花园相关 --------------------------
	&"watering":"res://assets/audio/SFX/garden/watering.ogg",
	&"fertilizer":"res://assets/audio/SFX/garden/fertilizer.ogg",
	&"bugspray":"res://assets/audio/SFX/garden/bugspray.ogg",
	&"phonograph":"res://assets/audio/SFX/garden/phonograph.ogg",
	&"wakeup": "res://assets/audio/SFX/garden/wakeup.ogg",

}
## 按 [param option] 播放既有场景或反馈音效；操作、奖励与警告使用基础 SFX 通道。
func play_other_SFX(option: StringName) -> void:
	var selected: AudioStream = _select_stream(SFXOtherMap.get(option))
	if selected != null:
		var space: SFXSpace = SFXSpace.UI if option in CLEAR_FEEDBACK else SFXSpace.COMBAT # 基础 SFX 也可以被当前场景的全局水下链统一处理。
		play_sfx_with_pool(selected, 0.0, 1.0, true, space)


#endregion

#endregion

#region 按钮信号连接辅助函数
## 更新开始菜单的UI音效
func setup_ui_start_menu_sound(node:Node, is_menu_button:=false):
	if node is BaseButton:
		var button := node
		button.mouse_entered.connect(play_other_SFX.bind("bleep"))

		if is_menu_button:
			button.button_down.connect(play_other_SFX.bind("gravebutton"))
		else:
			if not button.button_down.is_connected(play_other_SFX):
				button.button_down.connect(play_other_SFX.bind("tap"))


	for child in node.get_children():
		## 如果是Menu或者其上面的节点为Menu
		if child.name == "Menu" or is_menu_button:
			setup_ui_start_menu_sound(child, true)
		else:
			setup_ui_start_menu_sound(child, false)


## 更新主游戏按钮的UI音效
func setup_ui_main_game_sound(node:Node):
	if node is BaseButton:
		if node is CheckButton:
			node.pressed.connect(play_other_SFX.bind("buttonclick"))
		else:
			node.button_down.connect(play_other_SFX.bind("gravebutton"))

			if node.name == "Return":
				node.pressed.connect(play_other_SFX.bind("buttonclick"))


	for child in node.get_children():
		setup_ui_main_game_sound(child)
#endregion

#region 音量大小调整
func get_volum(bus_index:int):
	var db := AudioServer.get_bus_volume_db(bus_index)
	return db_to_linear(db)

func set_volume(bus_index:int, v:float) ->void:
	var db := linear_to_db(v)
	AudioServer.set_bus_volume_db(bus_index, db)
#endregion
