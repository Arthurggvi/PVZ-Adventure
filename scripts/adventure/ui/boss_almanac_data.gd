## Boss 图鉴的只读目录；属性取自注册场景及对应遭遇，技能说明随查看阶段变化。
extends RefCounted

## 行动间隔与救主实战共用。
const SaviorActions = preload("res://scripts/character/zombie_boss/savior/savior_action_tree.gd")

## 凯莱赫图鉴展示边境雪山噩梦遭遇的生命与登场波次。
const CAILLEACH_ENCOUNTER = preload("res://resources/adventure/stages/encounters/wonderland_snow_mountains_cailleach.tres")
## 描述雪暴时读取实际出弹数量和伤害；图鉴不实例化弹幕。
const CailleachHowl = preload("res://scripts/character/zombie_boss/cailleach/cailleach_howl_blizzard.gd")

## 黑将军稳定编号，供界面与预览共用。
const GENERAL: int = CharacterRegistry.ZombieBossType.ZB002BlackGeneral
## 白爵士稳定编号，沿用战斗注册表。
const DUKE: int = CharacterRegistry.ZombieBossType.ZB003WhiteDuke
## 明灯稳定编号，对应深海舞台。
const LANTERN: int = CharacterRegistry.ZombieBossType.ZB004MingLantern
## 救主稳定编号，图鉴和关卡预览共用头像。
const SAVIOR: int = CharacterRegistry.ZombieBossType.ZB005Savior
## 妇人（凯莱赫）的稳定编号，两个阶段共用一个档案。
const CAILLEACH: int = CharacterRegistry.ZombieBossType.ZB006Cailleach
## 提供双阶段预览的 Boss 目录。
const TYPES: Array[int] = [GENERAL, DUKE, LANTERN, SAVIOR, CAILLEACH]
## 注册场景或所需战斗配置缺失时显示的图鉴提示。
const DETAILS_UNAVAILABLE := "图鉴战斗资料暂不可用。"
## 图鉴的缩小版深海棋盘，在打开明灯详情时准备。
const LANTERN_STAGE := "res://assets/adventure/zombies/ming_lantern/preview_board.webp"
## 奇境资源存在时沿用教堂底图，打开详情时准备。
const SAVIOR_STAGE := "res://assets/adventure/wonderland/battle/zombie_church/board.png"
## 用户提供的人物介绍，保留原文和标点。
const STORIES: Dictionary = {
	SAVIOR: "一个族群要有他们的信仰，于是一位神诞生了",
	CAILLEACH: "她高高而立，\n斑点头巾裹住苍老的头，\n长长灰发在肩头飘流。\n有时着袜，\n更多时候踝骨裸露，\n一身黄袍总不离身。\n冬日里，女人们望见她\n驱着鹿群，向岸边走去。",
	LANTERN: "“传说古老的水域有神奇的魔法，喝下那斑斓的水可以获得无上的快乐。在那惊涛中中住着一位守护神，惩罚贪婪的盗贼，又为勇敢的水手展示倒影里的星辰。”",
	CharacterRegistry.ZombieBossType.ZB002BlackGeneral: "他每天清晨都会巡视一遍领地，主要目的是确认昨天放在窗台上的午餐肉罐头战利品没有被风偷走。没人敢告诉他，罐头其实是被白爵士拿走的；黑将军只是在日记里写：“敌人狡猾，且懂得分享。”",
	CharacterRegistry.ZombieBossType.ZB003WhiteDuke: "“我在研究一种真正的音乐风格，能让腐朽的灵魂们从坟中再度归来！”\n“你知道的，真正的艺术家不会停止创新。”\n“什么？你问我的头发是不是天然的??”\n“拜托，我从不染发，谁都知道我有最自然的天然蓝发。”\n“......色盲？我听不懂你在说什么。”",
}
## 纯视觉资源不携带 Boss 的技能执行器、碰撞、血量或奖励。
const VISUALS: Dictionary = {
	SAVIOR: "res://scenes/character/zombie_boss/savior_visual.tscn",
	CAILLEACH: "res://scenes/character/zombie_boss/cailleach_visual.tscn",
	LANTERN: "res://scenes/character/zombie_boss/ming_lantern_presentation.tscn",
	CharacterRegistry.ZombieBossType.ZB002BlackGeneral: "res://scenes/character/zombie_boss/black_general_visual.tscn",
	CharacterRegistry.ZombieBossType.ZB003WhiteDuke: "res://scenes/character/zombie_boss/white_duke_visual.tscn",
}

## Boss目录头像独立于完整战斗场景；裁切资源来自原有头像UV。
const PORTRAITS := {
	GENERAL: "res://assets/adventure/zombies/black_general/portrait.png",
	DUKE: "res://assets/adventure/zombies/white_duke/portrait.png",
	LANTERN: "res://assets/adventure/zombies/ming_lantern/portrait.png",
	SAVIOR: "res://assets/adventure/zombies/savior/portrait.res",
	CAILLEACH: "res://assets/adventure/zombies/cailleach/portrait.res",
}

static func portrait(type_id: int) -> Texture2D:
	var path: String = PORTRAITS.get(type_id, "")
	return load(path) as Texture2D if not path.is_empty() else null

## 返回按 [param search] 过滤的 Boss 目录；直接开放查看，不写入玩家发现记录。
static func rows(search: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 只返回显示身份。
	var needle: String = search.strip_edges().to_lower() # 与其他图鉴类别使用相同搜索规则。
	for type_id: int in TYPES: # 沿用稳定的 Boss 目录顺序。
		var title: String = title_for(type_id) # 本页名称。
		if needle.is_empty() or title.to_lower().contains(needle):
			var caption: String = "妇人" if type_id == CAILLEACH else title # 窄头像卡使用阶段简称，搜索与悬停使用全名。
			result.append({"kind": "boss", "type_id": type_id, "title": title, "caption": caption})
	return result

## 返回 [param type_id] 的中文名；未知编号返回空字符串。
static func title_for(type_id: int) -> String:
	match type_id:
		GENERAL: return "黑将军"
		DUKE: return "白爵士"
		LANTERN: return "明灯"
		SAVIOR: return "救主"
		CAILLEACH: return "妇人（凯莱赫）"
	return ""

## 从 [param type_id] 的注册场景读取只读资料；场景缺失或根节点无效时返回空字典。
static func profile(type_id: int) -> Dictionary:
	if not TYPES.has(type_id):
		return {}
	var packed := Global.character_registry.get_zombie_boss_info(
		type_id, CharacterRegistry.ZombieBossInfoAttribute.BossScenes) as PackedScene # 实战注册场景。
	if packed == null or not packed.can_instantiate():
		return {}
	var instance: Node = packed.instantiate() # 离树读取，避免执行出战初始化。
	var source := instance as ZB000Base # 只有注册的 Boss 根节点提供这些属性。
	var hp: HpComponent = source.get_node_or_null("HpComponent") as HpComponent if source != null else null # 与实战一致的最大生命来源。
	if hp == null:
		if instance != null:
			instance.free()
		return {}
	var max_health: int = hp.max_hp # 默认展示物种注册场景的最大生命。
	if type_id == CAILLEACH:
		max_health = CAILLEACH_ENCOUNTER.resolve_max_health(max_health)
	var result: Dictionary = {
		"title": source.get_boss_display_name(1),
		"phase_two_title": source.get_boss_display_name(2),
		"health": max_health,
		"threshold": source.phase_two_threshold_ratio,
		"inclusive": source.phase_two_threshold_inclusive,
		"portrait": source.boss_portrait_texture,
		"config": source.get("config") if type_id in [GENERAL, DUKE] else null,
		"story": STORIES.get(type_id, ""),
	} # 资源保持只读引用，临时节点随后释放。
	if type_id == GENERAL:
		var visual := source.get_node_or_null("Body/BlackGeneralVisual") as Node2D # 实战模型比例，供冲锋预览使用。
		if visual != null:
			result["visual_transform"] = visual.transform
	source.free()
	return result

## 判断 [param info] 是否具备 [param type_id] 的战斗详情和预览所需资料。
static func has_battle_details(type_id: int, info: Dictionary) -> bool:
	if info.is_empty():
		return false
	match type_id:
		GENERAL: return info.get("config") is BlackGeneralConfig and info.has("visual_transform")
		DUKE: return info.get("config") is WhiteDukeConfig
		LANTERN, SAVIOR, CAILLEACH: return true
	return false

## 返回 [param type_id] 在 [param phase] 的行动间隔秒数，取自 [param info] 对应的战斗配置。
## 缺少所需资料时返回 [code]NAN[/code]，供调用者识别无可显示的数值。
static func action_interval(type_id: int, info: Dictionary, phase: int) -> float:
	if not has_battle_details(type_id, info):
		return NAN
	if type_id == LANTERN:
		return MingLanternBehaviorTree.TURN_INTERVAL
	if type_id == CAILLEACH:
		return ZB006Cailleach.PHASE_TWO_INTERVAL if phase == 2 else ZB006Cailleach.PhaseOne.INTERVAL
	if type_id == SAVIOR:
		var intervals: Vector2 = SaviorActions.PRAYER_SECONDS # 两阶段共用实战祷告时钟，单位为战斗秒。
		return intervals.y if phase == 2 else intervals.x
	if type_id == GENERAL:
		var config: BlackGeneralConfig = info.config # 黑将军的两阶段等待间隔。
		return config.phase_two_action_interval if phase == 2 else config.phase_one_action_interval
	return (info.config as WhiteDukeConfig).action_delay(phase)

## 为 [param type_id]、[param phase] 和场景资料 [param info] 返回技能、说明及动画序列。
## 多个技能共用施法动作时保留实战对应关系，不虚构其他动作。
static func skills(type_id: int, phase: int, info: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 每个条目提供稳定 ID、名称、效果和纯视觉动作序列。
	if not has_battle_details(type_id, info):
		return result
	var second: bool = phase == 2 # 当前预览阶段。
	if type_id == SAVIOR:
		return _savior_skills(second)
	if type_id == CAILLEACH:
		return _cailleach_skills(second)
	if type_id == LANTERN:
		result.append(_skill("entrance", "登场", "五根青色灯条错峰坠落，六路依次涌浪。海面强光闪烁，明灯伴随海雷声与震动分段进入。", [&"entrance"]))
		result.append(_skill("guide", "引路", "眨眼、震屏，召唤 %d 根灯条。灯条有 2000 生命，落下时对植物造成 300 点伤害，闪烁十秒后引发 3×3 的水下爆炸，基础伤害 8000。" % (6 if second else 5), [&"guide"]))
		result.append(_skill("anchor", "锚定", "眨眼后召唤青光巨锚，碾压落点周围 3×3 内的植物。", [&"anchor"]))
		result.append(_skill("tide", "海啸", "眨眼、震屏，六路各出现一道浪。浪把命中的植物连同左侧相邻植物向左推 %d 格，最左端无处可退的植物会被碾压。僵尸受 100 点基础伤害并向左移一格。" % (2 if second else 1), [&"tide"]))
		result.append(_skill("shock", "震荡", "眨眼后释放两次白色震颤，每次影响 5×5。植物冻结 3 秒后减速 4 秒，僵尸减速 6 秒。", [&"shock"]))
		result.append(_skill("tidal", "滔天", "明灯缓慢退入深海，期间免疫伤害。投下 %d 根灯条，再送出五道浪。浪引爆扫过的灯条并释放震颤，中心巨锚触地时引发震荡。%s" % [7 if second else 5, "生命低于一半时立即发动强化滔天。余震共享命中记录，首次回场时显露星空形态。" if second else "明灯随后分段回场。"], [&"tidal"]))
		result.append(_skill("death", "退场", "明灯死亡时，全场僵尸一并死亡。随后屏幕剧烈震动，明灯沉向深海。", [&"death"]))
	elif type_id == GENERAL:
		var config := info.config as BlackGeneralConfig # 黑将军数值来自场景。
		result.append(_skill("flag", "插旗", "在前方一格插下生命为 %d 的令旗，为全场敌方僵尸及 Boss 提供 %d 点格挡。令旗被摧毁后效果消失；插旗冷却 %s 秒，场上已有令旗时不会重复插旗。" % [config.flag_health, config.phase_two_block if second else config.phase_one_block, config.flag_cooldown], [&"raise"]))
		result.append(_skill("command", "号令", "召来一波%s援军，总数为场地行数 × %d。援军从普通、路障、撑杆、铁桶和橄榄球僵尸中抽取。" % ["二阶" if second else "一阶", config.command_per_lane], [&"raise"]))
		result.append(_skill("charge", "冲锋", "蓄力后以 %s 像素/秒冲锋，每株植物承受 %d 点穿透伤害；%s。冲锋不会进入前两列。%s" % [config.charge_speed, config.charge_damage, "不限制击杀数量" if second else "击杀 %d 株植物后停止" % config.phase_one_kill_limit, "沿途留下三个剪影设施。" if second else ""], [&"windup", &"charge", &"charge_stop"]))
		result.append(_skill("lead", "统领", "在当前行前方一格召唤一名三阶橄榄球僵尸。", [&"raise"]))
		result.append(_skill("move", "换行", "移动到另一行，改变后续插旗、冲锋和统领的路线；普通技能与换行交替进行。", [&"run"]))
		result.append(_skill("entrance", "登场", "传送入场并举旗，在第 2、4 路各召唤一名一阶全明星僵尸。", [&"teleport_in", &"raise"]))
		if second:
			result.append(_skill("transition", "转阶段", "达到阶段转换生命阈值后，转阶段期间无敌；按第 1、5 路，第 2、4 路，第 3 路的顺序召唤全明星。随后本体与残影扫掠场地，已有令旗升级为二阶段格挡。", [&"raise", &"teleport_out", &"teleport_in", &"windup", &"charge", &"charge_stop", &"teleport_out", &"teleport_in", &"raise"]))
	else:
		var config := info.config as WhiteDukeConfig # 白爵士数值来自场景。
		result.append(_skill("resurrect", "复生", "生成 %d 块墓碑，从最近 %s 秒内死亡的僵尸中抽取最多同等数量复活，并保留原等阶。墓碑不会放在前 %d 列。" % [config.skill_graves + (config.skill_graves_phase2_bonus if second else 0), config.recent_death_window, config.minimum_grave_column], [&"point"]))
		result.append(_skill("command", "号令", "在第 2、4 路各召唤一名%s舞王僵尸。%s" % ["三阶" if second else "二阶", "另外在第 1、3、5 路各召唤一名一阶舞王僵尸。" if second else ""], [&"point"]))
		result.append(_skill("frenzy", "狂热", "使全场存活且未被魅惑的普通僵尸获得 %s 倍移动速度，持续 %s 秒，并获得 %s 秒伤害免疫。" % [config.fury_speed_multiplier, config.fury_seconds, config.immunity_seconds], [&"point"]))
		result.append(_skill("breach", "破阵", "在每一路各召唤一名%s报纸僵尸。" % ("三阶" if second else "二阶"), [&"point"]))
		result.append(_skill("move", "换行", "移动到另一行，并在可用位置生成一块墓碑；普通技能与换行交替进行。", [&"walk"]))
		result.append(_skill("entrance", "登场", "传送入场并生成 %d 块墓碑，复活上一旗帜波阵亡的僵尸。" % config.entrance_graves, [&"teleport_in", &"point"]))
		if second:
			result.append(_skill("transition", "转阶段", "在最后 %d 列铺设墓碑，复活最近 %s 秒内最多 %d 名阵亡僵尸，给予 %s 秒的 %s 倍移速和伤害免疫；白爵士在演出期间无敌并传送归位。" % [config.phase_grave_columns, config.recent_death_window, config.phase_revival_limit, config.immunity_seconds, config.fury_speed_multiplier], [&"point", &"teleport_out", &"teleport_in"]))
	return result

## 返回凯莱赫的战斗条目；[param second] 决定施法方式和强化技能的数值。
static func _cailleach_skills(second: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 文字机制卡仍可独立查看；杖击卡复用图鉴现有动作。
	if second:
		result.append(_skill("transition", "显现", "生命跌破一半后，妇人消失在雪雾中。地震让三条路依次崩落，板块上的植物和僵尸都会死亡。沉下的路线在本场战斗中关闭。随后，凯莱赫从暴雪中现身。", []))
		result.append(_skill("anger", "愠怒", "她在骤强的暴雪中化作白色剪影，期间免疫伤害。眼部闪起白光时技能生效。风雪平息、她重新现身后，才开始下一轮倒计时。", []))
	else:
		result.append(_skill("entrance", "登场", "噩梦第 %d 波清场后，妇人从雪雾中传送入场。她以杖击随机冰封约一半植物，并让全场植物减速 %d 秒。" % [
			CAILLEACH_ENCOUNTER.wave, roundi(ZB006Cailleach.SkillEffects.ENTRANCE_SLOW_SECONDS)], []))
		result.append(_skill("staff", "杖击", "手杖触地时，狂风卷着雪横扫战场，伴随白闪和一声清脆的鸣响。一阶段的技能在手杖落地时生效。", [&"staff"]))
	var aurora_count: int = ZB006Cailleach.PHASE_TWO_AURORAS if second else ZB006Cailleach.PhaseOne.AURORA_COUNT # 当前阶段每次召来的极光。
	var grief_layers: int = ZB006Cailleach.PHASE_TWO_AURORA_GRIEF if second else ZB006Cailleach.PhaseOne.AURORA_GRIEF # 单枚极光提供的悲寒层数。
	var lane_limit: int = ZB006Cailleach.PHASE_TWO_HOWL_LANES if second else CailleachHowl.LANE_LIMIT # 当前阶段最多发动雪暴的路数。
	var lane_shots: int = ZB006Cailleach.PHASE_TWO_HOWL_SHOTS if second else CailleachHowl.SHOTS_PER_LANE # 每路雪弹总数。
	var grief_limit: int = ZB006Cailleach.SkillEffects.Grief.MAX_STACKS # 达到这个层数后植株完全停止行动。
	result.append_array([
		_skill("sleep", "沉眠吧", "随机冰封最多 %d 株植物。冰壳解除前，被冰封的植物无法行动。" % ZB006Cailleach.SkillEffects.SLEEP_TARGETS, []),
		_skill("aurora", "仰望", "在随机位置错落降下 %d 枚极光。每枚对落点周围 3×3 内的植物造成其最大生命 %d%% 的基础伤害。存活的植物叠加 %d 层悲寒。" % [
			aurora_count, roundi(100.0 * ZB006Cailleach.SkillEffects.AURORA_HP_FRACTION), grief_layers], []),
		_skill("rest", "安息吧", "场上同时存在完全悲寒与冰冻时才有机会施放。所有完全悲寒或冰冻的植物立即消散。每消散 1 株，同类植物卡的剩余冷却增加 1 秒。", []),
		_skill("howl", "呼啸", "随机在最多 %d 路释放雪暴。雪弹沿坡面从右向左飞行，各对碰到的第一株植物造成 %d 点基础伤害。每路合计最多造成 %d 点基础伤害。" % [
			lane_limit, CailleachHowl.DAMAGE, lane_shots * CailleachHowl.DAMAGE], []),
		_skill("grief", "悲寒", "每层使植物的行动速度降低 %d%%，颜色更偏蓝白。叠满 %d 层后即为完全悲寒，植物停止行动，化成蓝白色剪影。" % [
			roundi(100.0 / grief_limit), grief_limit], []),
	])
	if second:
		result.append(_skill("death", "退场", "凯莱赫死亡时，暴雪骤强，%d 枚极光先后坠落。每枚立即消灭落点周围 3×3 内的僵尸，并冰封范围内的植物。随后她隐入风雪，雪势逐渐平息。" % ZB006Cailleach.SkillEffects.DEATH_AURORAS, []))
	return result

## 返回救主的登场、五种祷告及 [param second] 阶段解锁的分裂说明。
static func _savior_skills(second: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = [ # 普通技能共用原画中的祷告动作。
		_skill("entrance", "登场", "传送入场后祷告并黑闪熄灯，使所有亡影复生为信徒，并对所有未被路灯花照到的植物造成 1000 点伤害。随后震屏，从自身向上下左右各发射一道红色光柱，对命中的植物造成 100 点伤害并施加 30% 劣化。", [&"teleport_in", &"pray"]),
		_skill("void", "没入无垠", "祷告后黑闪熄灯，先对所有未被路灯花照到的植物造成 1000 点伤害，再使所有亡影复生为信徒。场上有可复生的亡影时才会抽到此技能。", [&"pray"]),
		_skill("madness", "没入疯狂", "祷告后剧烈震屏，六道猩红光柱围绕自身旋转并向外扩散。触及的僵尸获得 4 秒无敌和 4 秒移速 +100%，触及的植物受到 2 秒眩晕和 30% 劣化。", [&"pray"]),
		_skill("peace", "没入安乐", "祷告后黑闪，从存活的敌方普通僵尸中随机将至多 8 只转化为信徒。", [&"pray"]),
		_skill("despair", "没入绝望", "祷告后在四个随机格子降下血色流光，每束对落点周围 3×3 内的植物造成 200 点伤害。范围内有路灯花时，由最近的一株吸收这束流光，仅对该路灯花造成 100 点伤害。", [&"pray"]),
		_skill("gospel", "没入福音", "祷告后随机锁定一株未占用前两列的植物，在其所在格召唤拥有 4000 点生命的白色光柱，同格植物也能攻击光柱。若 12 秒内未击破光柱，或锁定的植物成功换格，光柱会转为猩红色，立即湮灭该植物并为施法的救主恢复 6000 点生命。", [&"pray"]),
	]
	if second:
		result.append(_skill("transition", "转阶段", "生命低于一半时，救主祷告并黑闪熄灯，暂时失去光照。在教堂第 6 列的第 2、4 行各出现一个暂时无光的分身。本体和分身各有 20000 点生命，独立承伤、独立死亡，底部 Boss 血条仍显示生命总和。\n时停冻结全场活动、种植和产卡。镜头依次特写本体、第 2 行分身、第 4 行分身。每位在特写中亮起光照，以半速祷告并停在举手帧。镜头和时间恢复后，三位保持举手姿势同时重演入场攻击，演出结束后收手。", [&"pray"]))
	return result

## 返回 [param type_id] 在 [param phase] 的当前特性，数值读取 [param info]，不提前混入下一阶段机制。
static func passive(type_id: int, info: Dictionary, phase: int) -> String:
	if not has_battle_details(type_id, info):
		return DETAILS_UNAVAILABLE
	if type_id == SAVIOR:
		return _savior_passive(phase)
	if type_id == CAILLEACH:
		return "冰封会给植物套上猎人僵尸的冰壳，耐久为 %d。冰壳解除前，植物无法行动。" % PlantIceShell.MAX_HP
	if type_id == LANTERN:
		var tidal: String = "每完成 %d 轮普通行动，下一轮必定释放滔天。" % MingLanternBehaviorTree.TIDAL_AFTER # 读取实战计数门槛。
		return tidal + ("每轮随机连放两个不同技能，浪扫过的灯条立即自爆。" if phase == 2 else "每轮随机释放一个技能，植物可在灯条自爆前击毁它。")
	if type_id == GENERAL:
		var general := info.config as BlackGeneralConfig # 令旗格挡与冲锋上限随阶段变化。
		if phase == 1:
			return "令旗提供 %d 点格挡；冲锋击杀 %d 株植物后停止。技能与换行交替进行。" % [general.phase_one_block, general.phase_one_kill_limit]
		return "黑焰形态，令旗格挡提升至 %d 点。冲锋不限击杀数量，并沿途留下三个剪影。" % general.phase_two_block
	var config := info.config as WhiteDukeConfig # 墓碑被动在两个阶段均生效。
	var revival: String = ( # 与场景中的墓碑数值和触发来源一致。
		"白爵士召出的墓碑拥有普通墓碑 %d%% 的生命，前 %s 秒无法自主复生。"
		+ "墓碑每 %s 秒、白爵士每 %s 秒尝试复生。白爵士可立即使用新墓碑。"
		+ "由其墓碑能力出土的僵尸以 %d%% 移动速度入场，持续 %s 秒。"
	) % [roundi(PvZ2AttackableTombstone.WHITE_DUKE_HEALTH_RATIO * 100.0),
		String.num(config.grave_auto_revive_min_age, 1).trim_suffix(".0"),
		String.num(config.grave_auto_revive_seconds, 1).trim_suffix(".0"),
		String.num(config.grave_boss_revive_seconds, 1).trim_suffix(".0"),
		roundi(WhiteDukeConfig.GRAVE_ENTRY_SPEED_MULTIPLIER * 100.0),
		String.num(config.grave_entry_slow_seconds, 1).trim_suffix(".0")]
	return revival + ("召唤强化，并伴随彩色聚光灯。" if phase == 2 else "复活的僵尸保留原等阶。")

## 描述救主 [param phase] 的在场效果、随机祷告与信徒规则。
static func _savior_passive(phase: int) -> String:
	var presence: String = "本体只在第 3 行出场，始终留在该行。救主在场时，亡影不会因光源破散，自然生成的僵尸全部为四阶普通僵尸。" # 两阶段均适用的在场规则。
	var follower: String = "信徒是普通僵尸的黑色剪影，免疫所有伤害。对碰到的第一株植物造成 8000 点伤害后破散，碰到路灯花时只造成 50 点伤害。" # 两阶段的信徒规则相同。
	if phase == 2:
		return presence + "自然出怪数量减为一阶段的一半。\n存活的本体和分身同步施放同一个随机技能。没入无垠和没入安乐每轮只结算一次。打开暂停菜单后，战斗仍会继续。\n" + follower
	return presence + "自然出怪数量大幅增加。行动树每轮随机施放一个可用技能。\n" + follower

## 将 [param id]、[param title]、[param description]、[param clips] 包装成只读展示条目。
static func _skill(id: String, title: String, description: String, clips: Array[StringName]) -> Dictionary:
	return {"id": id, "title": title, "description": description, "clips": clips}
