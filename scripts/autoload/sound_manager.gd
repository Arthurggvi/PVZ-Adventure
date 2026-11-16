extends Node
class_name SoundManagerClass

enum Bus {MASTER, BGM, SFX}

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

## [param path] 为音效路径；统一缓存流资源，解析失败返回 null。
func _stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		push_error("SoundManager: invalid SFX resource " + path)
		return null
	_stream_cache[path] = stream
	return stream

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
## 返回实际使用的播放器，播放被合并时返回 null。
func play_sfx_with_pool(sfx_resource: AudioStream, volume_db: float = 0.0,
		pitch_scale: float = 1.0, deduplicate_in_frame: bool = true) -> AudioStreamPlayer:
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
	player.stream = sfx_resource
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return player

#TODO: 好像没什么用,后续会删掉
@warning_ignore("unused_parameter")
func _on_sfx_finished(player: AudioStreamPlayer):
	# 播放完成后自动停止，保留在池中
	#player.stop()
	pass

## 播放僵尸受击音效
func play_be_attack_SFX(type_bullet_zombie_sfx: TypeBeAttackSFX) -> void:
	var selected: AudioStream = _select_stream(SFXBeAttackMap.get(type_bullet_zombie_sfx))
	if selected != null:
		play_sfx_with_pool(selected)

func play_bullet_attack_SFX(type_bullet_sfx: TypeBulletSFX) -> void:
	var selected: AudioStream = _select_stream(SFXBulletMap.get(type_bullet_sfx))
	if selected != null:
		play_sfx_with_pool(selected)

func play_character_SFX(option: StringName) -> AudioStreamPlayer:
	var selected: AudioStream = _select_stream(SFXCharacterMap.get(option))
	return play_sfx_with_pool(selected) if selected != null else null

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
## 播放其它相关音效
func play_other_SFX(option: StringName) -> void:
	var selected: AudioStream = _select_stream(SFXOtherMap.get(option))
	if selected != null:
		play_sfx_with_pool(selected)


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
