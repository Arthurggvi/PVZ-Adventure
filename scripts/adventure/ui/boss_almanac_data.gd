## Boss 图鉴的只读目录；战斗属性读取注册场景，技能说明按当前阶段生成。
extends RefCounted

## 本页两位拥有独立双阶段美术的 Boss，沿用战斗注册编号。
const TYPES: Array[int] = [CharacterRegistry.ZombieBossType.ZB002BlackGeneral, CharacterRegistry.ZombieBossType.ZB003WhiteDuke]
## 黑将军稳定编号，供界面与预览共用。
const GENERAL: int = CharacterRegistry.ZombieBossType.ZB002BlackGeneral
## 用户提供的人物介绍，保留原文和标点。
const STORIES: Dictionary = {
	CharacterRegistry.ZombieBossType.ZB002BlackGeneral: "他每天清晨都会巡视一遍领地，主要目的是确认昨天放在窗台上的午餐肉罐头战利品没有被风偷走。没人敢告诉他，罐头其实是被白爵士拿走的；黑将军只是在日记里写：“敌人狡猾，且懂得分享。”",
	CharacterRegistry.ZombieBossType.ZB003WhiteDuke: "“我在研究一种真正的音乐风格，能让腐朽的灵魂们从坟中再度归来！”\n“你知道的，真正的艺术家不会停止创新。”\n“什么？你问我的头发是不是天然的??”\n“拜托，我从不染发，谁都知道我有最自然的天然蓝发。”\n“......色盲？我听不懂你在说什么。”",
}
## 纯视觉资源不携带 Boss 的技能执行器、碰撞、血量或奖励。
const VISUALS: Dictionary = {
	CharacterRegistry.ZombieBossType.ZB002BlackGeneral: preload("res://scenes/character/zombie_boss/black_general_visual.tscn"),
	CharacterRegistry.ZombieBossType.ZB003WhiteDuke: preload("res://scenes/character/zombie_boss/white_duke_visual.tscn"),
}

## 返回按 [param search] 过滤的 Boss 目录；直接开放查看，不写入玩家发现记录。
static func rows(search: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 只返回显示身份。
	var needle: String = search.strip_edges().to_lower() # 与其他图鉴类别使用相同搜索规则。
	for type_id: int in TYPES: # 顺序为黑将军、白爵士。
		var title: String = title_for(type_id) # 本页名称。
		if needle.is_empty() or title.to_lower().contains(needle):
			result.append({"kind": "boss", "type_id": type_id, "title": title})
	return result

## 返回 [param type_id] 的中文名；未知编号返回空字符串。
static func title_for(type_id: int) -> String:
	if not TYPES.has(type_id):
		return ""
	return "黑将军" if type_id == GENERAL else "白爵士"

## 读取 [param type_id] 的场景默认属性，不把临时 Boss 加入场景树；未知编号返回空字典。
static func profile(type_id: int) -> Dictionary:
	if not TYPES.has(type_id):
		return {}
	var packed: PackedScene = Global.character_registry.get_zombie_boss_info(type_id, CharacterRegistry.ZombieBossInfoAttribute.BossScenes) # 实战注册场景。
	var source := packed.instantiate() as ZB000Base # 仅读取导出值，绝不运行出战初始化。
	var hp := source.get_node("HpComponent") as HpComponent # 与实战一致的最大生命。
	var result: Dictionary = {
		"title": source.boss_display_name,
		"health": hp.max_hp,
		"threshold": source.phase_two_threshold_ratio,
		"inclusive": source.phase_two_threshold_inclusive,
		"portrait": source.boss_portrait_texture,
		"config": source.get("config"),
		"story": STORIES[type_id],
	} # 资源保持只读引用，临时节点随后释放。
	if type_id == GENERAL:
		result["visual_transform"] = (source.get_node("Body/BlackGeneralVisual") as Node2D).transform
	source.free()
	return result

## 返回 [param info] 在 [param phase] 的行动间隔秒数，与实战使用同一份配置。
static func action_interval(info: Dictionary, phase: int) -> float:
	var config: Resource = info.config # 只读访问注册场景的行为配置。
	if config is BlackGeneralConfig:
		return config.phase_two_action_interval if phase == 2 else config.phase_one_action_interval
	return (config as WhiteDukeConfig).action_delay(phase)

## 为 [param type_id]、[param phase] 和场景资料 [param info] 返回技能、说明及动画序列。
## 多个技能共用施法动作时保留实战对应关系，不虚构其他动作。
static func skills(type_id: int, phase: int, info: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 每个条目提供稳定 ID、名称、效果和纯视觉动作序列。
	var second: bool = phase == 2 # 当前预览阶段。
	if type_id == GENERAL:
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

## 返回 [param type_id] 在 [param phase] 的当前特性，数值读取 [param info]，不提前混入下一阶段机制。
static func passive(type_id: int, info: Dictionary, phase: int) -> String:
	if type_id == GENERAL:
		var general := info.config as BlackGeneralConfig # 令旗格挡与冲锋上限随阶段变化。
		if phase == 1:
			return "令旗提供 %d 点格挡；冲锋击杀 %d 株植物后停止。技能与换行交替进行。" % [general.phase_one_block, general.phase_one_kill_limit]
		return "黑焰形态，令旗格挡提升至 %d 点。冲锋不限击杀数量，并沿途留下三个剪影。" % general.phase_two_block
	var config := info.config as WhiteDukeConfig # 墓碑被动在两个阶段均生效。
	var revival: String = "墓碑每 %s 秒尝试复生，白爵士每 %s 秒额外尝试一次。" % [String.num(config.grave_auto_revive_seconds, 1), String.num(config.grave_boss_revive_seconds, 1)] # 精简单位和重复措辞。
	return revival + ("召唤强化，并伴随彩色聚光灯。" if phase == 2 else "复活的僵尸保留原等阶。")

## 将 [param id]、[param title]、[param description]、[param clips] 包装成只读展示条目。
static func _skill(id: String, title: String, description: String, clips: Array[StringName]) -> Dictionary:
	return {"id": id, "title": title, "description": description, "clips": clips}
