## 地图悬停预览的视图模型：把已解析的关卡资源投影成纯展示字典。
## 只读既有目录与美术清单，不持有节点、不写存档，也不重新解释波次预算。
extends RefCounted

## 掉落投影与配方汇总只读取既有掉落表，保持奖励规则独立。
const Drops = preload("res://scripts/adventure/ui/stage_preview_drops.gd")
## Boss 名称和头像沿用图鉴从战斗场景读取的资料。
const BossData = preload("res://scripts/adventure/ui/boss_almanac_data.gd")

## 情报不可展示时只提供状态，关卡本身未解锁时不会请求预览。
const STATE_SEALED := "sealed"
## 情报可展示时附上关卡名与各阶段的内容。
const STATE_READY := "ready"

## 每个物种最多列出的波次区间数量，超出时以省略号收尾。
const MAX_WAVE_RANGES := 3

## 根据 [param normal_cleared] 决定是否展示情报。
## [param stage] 为已解析关卡，缺失时也显示问号；[param title] 仅用于完整情报。
## 完整字典附带类型文字与去重的配方候选；不读取库存或执行掉落。
static func build(stage: StageDefinition, title: String, normal_cleared: bool) -> Dictionary:
	if not normal_cleared or stage == null:
		return {"state": STATE_SEALED}
	Global.global_read_data.ensure_almanac_loaded() # 中文名与图鉴共用同一份数据，首次读取时加载。
	var blocks: Array[Dictionary] = [] # 按普通、噩梦、终末的顺序组织情报。
	for phase: StagePhaseDefinition in _ordered_phases(stage): # 每个可展示阶段生成一块情报。
		blocks.append(_block(phase))
	return {"state": STATE_READY, "title": title, "blocks": blocks,
		"type_text": _type_text(stage), "recipe_drops": Drops.recipe_summary(blocks)}

## 根据 [param stage] 已合并的环境规则与实际阶段生成类型文字，不根据底图颜色猜测。
## 阶段底图和环境滤镜不改写昼夜规则；黄昏沿用非白日且仍降自然阳光的配置。
static func _type_text(stage: StageDefinition) -> String:
	var types := PackedStringArray() # 环境在前，可挑战的后续阶段在后。
	var environment: AdventureBattleEnvironment = stage.environment # 包含单关覆盖后的环境配置。
	if environment == null:
		types.append("环境未配置")
	elif environment.daytime:
		types.append("白日")
	elif environment.daytime_sun:
		types.append("黄昏")
	else:
		types.append("夜晚")
	if AdventureStageCatalog.find_phase(stage, StagePhaseDefinition.Kind.NIGHTMARE) != null:
		types.append("噩梦")
	if AdventureStageCatalog.find_phase(stage, StagePhaseDefinition.Kind.TERMINAL) != null:
		types.append("终末")
	return " · ".join(types)

## 按 [param stage] 的挑战顺序列出已配置阶段。
static func _ordered_phases(stage: StageDefinition) -> Array[StagePhaseDefinition]:
	var result: Array[StagePhaseDefinition] = [] # 仅包含关卡实际配置的阶段。
	for kind: int in [StagePhaseDefinition.Kind.NORMAL, StagePhaseDefinition.Kind.NIGHTMARE, StagePhaseDefinition.Kind.TERMINAL]: # 续战顺序。
		var phase: StagePhaseDefinition = AdventureStageCatalog.find_phase(stage, kind) # 阶段可独立缺省。
		if phase != null:
			result.append(phase)
	return result

## 返回 [param phase] 的波次摘要、敌人、Boss 与掉落。
static func _block(phase: StagePhaseDefinition) -> Dictionary:
	var label: String = "普通阶段" # 预览分组的中文标题。
	var wave_text: String = "波次配置无效" # 波次或终末的胜利条件。
	if phase.kind == StagePhaseDefinition.Kind.NIGHTMARE:
		label = "噩梦阶段"
	elif phase.kind == StagePhaseDefinition.Kind.TERMINAL:
		label = "终末阶段"
		wave_text = "持续出怪 · 击败僵王博士"
	var profile: WaveProfile = phase.wave_profile # 终末阶段无波次表。
	if profile != null:
		wave_text = "%d 波 · 旗帜 %d 次" % [profile.wave_count, _flag_count(profile)]
	return {
		"phase": AdventureStageCatalog.phase_slug(phase.kind),
		"label": label,
		"wave_text": wave_text,
		"enemies": _enemies(phase),
		"bosses": _bosses(phase),
		"drops": Drops.from_table(phase.drop_table),
		"clear_drops": Drops.for_clear(phase.events),
	}

## 返回 [param profile] 的大波数；末波即使未写进 flag_waves，也与规划器一样计入。
static func _flag_count(profile: WaveProfile) -> int:
	var count: int = profile.flag_waves.size() # 显式旗帜波加上未重复计入的末波。
	if not profile.flag_waves.has(profile.wave_count):
		count += 1
	return count

## 返回 [param phase] 唯一名单中的敌人条目，等阶徽章只投影显示名与配色。
static func _enemies(phase: StagePhaseDefinition) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [] # 按权威名单原有顺序展示物种。
	for entry: Dictionary in AdventureStageRoster.entries(phase): # 复用波次和召唤合并后的唯一名单。
		var zombie_type: int = int(entry["type"]) # 用于名称、头像和类型识别的注册编号。
		if zombie_type <= 0: # 未配置的物种不参与展示。
			continue
		rows.append({
			"card_type": ResourceCardReference.CardType.Zombie,
			"type": zombie_type,
			"title": _zombie_name(zombie_type),
			"waves": _waves_text(entry["waves"]),
			"tiers": _tier_badges(entry["tiers"]),
		})
	return rows

## 返回 [param phase] 的 Boss 行，身份取自 Boss 图鉴，登场时机与掉落取自遭遇和事件配置。
static func _bosses(phase: StagePhaseDefinition) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [] # 按阶段遭遇顺序输出可展示的 Boss。
	for encounter: BossEncounterDefinition in phase.boss_encounters: # 各遭遇独立显示时机与奖励。
		if encounter == null or encounter.boss_type == CharacterRegistry.ZombieBossType.Null:
			continue
		var boss_type: int = int(encounter.boss_type) # 地图行、图鉴和战斗共用的编号。
		var profile: Dictionary = BossData.profile(boss_type) # 独立图鉴尚未收录的 Boss 返回空字典。
		var title: String = str(profile.get("title", "")) # 优先采用实战界面使用的名称。
		rows.append({
			"card_type": ResourceCardReference.CardType.ZombieBoss,
			"type": boss_type,
			"title": title if not title.is_empty() else _boss_name(boss_type),
			"portrait": profile.get("portrait"),
			"timing": _timing_text(encounter),
			"drops": Drops.for_boss(phase.events, encounter.encounter_id),
		})
	return rows

## 将 [param ranges] 转为波次区间文字；没有固定波次的物种由 Boss 或事件召唤产生。
static func _waves_text(ranges: Array) -> String:
	if ranges.is_empty():
		return "额外召唤"
	var parts := PackedStringArray() # 最多显示约定数量的区间，再补省略标记。
	for index: int in range(mini(ranges.size(), MAX_WAVE_RANGES)): # 按已有区间顺序截取。
		var value: Vector2i = ranges[index] # 区间起止波次，包含两端。
		parts.append("第 %d 波" % value.x if value.x == value.y else "第 %d–%d 波" % [value.x, value.y])
	if ranges.size() > MAX_WAVE_RANGES:
		parts.append("…")
	return "、".join(parts)

## 将 [param tiers] 投影为名称与配色徽章，按等阶目录升序排列。
static func _tier_badges(tiers: Array) -> Array[Dictionary]:
	var badges: Array[Dictionary] = [] # 只保留本物种实际使用且已登记的等阶。
	for tier_id: StringName in AdventureZombieTierCatalog.tier_ids(): # 保持权威目录的显示次序。
		if not tiers.has(tier_id):
			continue
		var definition: Dictionary = AdventureZombieTierCatalog.get_tier(tier_id) # 名称和颜色来自同一目录。
		if definition.is_empty():
			continue
		badges.append({
			"label": AdventureZombieTierCatalog.display_name(tier_id),
			"color": definition["tint"],
		})
	return badges

## 返回 [param zombie_type] 的图鉴中文名；未登记时退回编号，避免空标题。
static func _zombie_name(zombie_type: int) -> String:
	if Global.character_registry == null or Global.global_read_data == null:
		return "僵尸 #%d" % zombie_type
	if not Global.character_registry.ZombieInfo.has(zombie_type):
		return "僵尸 #%d" % zombie_type
	var key := str(Global.character_registry.get_zombie_info( # 注册键用于读取既有图鉴翻译。
		zombie_type as CharacterRegistry.ZombieType,
		CharacterRegistry.ZombieInfoAttribute.ZombieName))
	var entry: Dictionary = Global.global_read_data.data_almanac.get("Zombie", {}).get(key, {}) # 已加载的图鉴条目。
	return str(entry.get("名字", "僵尸 #%d" % zombie_type))

## 从旧版图鉴查找 [param boss_type] 的名称，供独立 Boss 图鉴尚未收录的角色使用。
static func _boss_name(boss_type: int) -> String:
	if Global.character_registry == null or Global.global_read_data == null:
		return "僵王 #%d" % boss_type
	if not Global.character_registry.ZombieBossInfo.has(boss_type):
		return "僵王 #%d" % boss_type
	var key := str(Global.character_registry.get_zombie_boss_info( # 旧图鉴的 Boss 注册键。
		boss_type as CharacterRegistry.ZombieBossType,
		CharacterRegistry.ZombieBossInfoAttribute.BossName))
	var entry: Dictionary = Global.global_read_data.data_almanac.get("ZombieBoss", {}).get(key, {}) # 兼容未迁移的 Boss 名称。
	return str(entry.get("名字", "僵王 #%d" % boss_type))

## 返回 [param encounter] 登场时机的中文说明，未知时机明确提示未配置。
static func _timing_text(encounter: BossEncounterDefinition) -> String:
	match encounter.timing:
		BossEncounterDefinition.Timing.PHASE_START:
			return "开场登场"
		BossEncounterDefinition.Timing.WAVE_BEFORE:
			return "第 %d 波前登场" % encounter.wave
		BossEncounterDefinition.Timing.WAVE_STARTED:
			return "第 %d 波登场" % encounter.wave
		BossEncounterDefinition.Timing.WAVE_CLEARED:
			return "第 %d 波清场后登场" % encounter.wave
		BossEncounterDefinition.Timing.EVENT_ONLY:
			return "由事件召唤"
	return "登场时机未配置"
