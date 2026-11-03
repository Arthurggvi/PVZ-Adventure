## 单个 normal/nightmare 阶段的静态契约；选卡和僵尸预览始终必需。
extends Resource
class_name StagePhaseDefinition

## 阶段身份必须显式指定，不由名字或数组位置推断。
enum Kind { UNSET, NORMAL, NIGHTMARE }
## nightmare 必须先通关本关 normal；钥匙条件可与该阶段锁组合。
enum UnlockRule { UNSET, OPEN, KEY, NORMAL_CLEARED, NORMAL_CLEARED_AND_KEY }
## 无钥匙条件、检查但保留、检查并消费三种语义明确分离。
enum KeyUse { UNSET, NOT_REQUIRED, KEEP, CONSUME }
## 仅主动选卡兼容本阶段契约，其他模式保留为可报告的非法配置。
enum CardMode { UNSET, CHOOSE_CARDS, FIXED_DECK, CONVEYOR, COIN }
## 阶段稳定 ID，在当前关卡内唯一。
@export var phase_id: StringName = &""
## normal 或 nightmare，不预设有效阶段。
@export var kind: Kind = Kind.UNSET
## 显式阶段锁条件。
@export var unlock_rule: UnlockRule = UnlockRule.UNSET
## 需要的静态钥匙 ID，非钥匙条件必须为空。
@export var key_id: StringName = &""
## 需要检查的钥匙数量，非钥匙条件必须为 0。
@export var key_count: int = 0
## 是否消费钥匙必须由配置者选择，不预填游戏规则。
@export var key_use: KeyUse = KeyUse.UNSET
## 必须为 true，不能由任何模式或 Boss 配置绕过。
@export var require_card_selection: bool = true
## 必须为 true，不依赖是否有自然波次或 Boss。
@export var require_zombie_preview: bool = true
## 必须选择兼容强制选卡的模式。
@export var card_mode: CardMode = CardMode.UNSET
## 当前阶段的出战槽数，必须与原版卡槽支持范围兼容。
@export_range(0, 15) var max_selected_cards: int = 0
## 自然波次与分波段物种/等阶权重。
@export var wave_profile: WaveProfile
## 独立掉落表；此处只引用，不执行奖励。
@export var drop_table: DropTable
## 当前阶段的 Boss 遭遇元数据，可为空。
@export var boss_encounters: Array[BossEncounterDefinition] = []
## 当前阶段的事件元数据，可为空。
@export var events: Array[StageEventDefinition] = []

## [param known_tier_ids]、[param known_key_ids] 由实际定义方提供，不读取单例或玩家资产。
func validate(known_tier_ids: Array[StringName] = [], known_key_ids: Array[StringName] = []) -> PackedStringArray:
	var errors := PackedStringArray() # 当前阶段全部错误，不改变资源。
	if str(phase_id).strip_edges().is_empty():
		errors.append("阶段缺少稳定 ID。")
	if kind not in [Kind.NORMAL, Kind.NIGHTMARE]:
		errors.append("阶段类型必须为 normal 或 nightmare。")
	if kind == Kind.NORMAL and unlock_rule not in [UnlockRule.OPEN, UnlockRule.KEY]:
		errors.append("normal 必须显式选择开放或钥匙条件，不能依赖自身通关。")
	if kind == Kind.NIGHTMARE and unlock_rule not in [UnlockRule.NORMAL_CLEARED, UnlockRule.NORMAL_CLEARED_AND_KEY]:
		errors.append("nightmare 必须先完成本关 normal。")
	if unlock_rule == UnlockRule.UNSET or not UnlockRule.values().has(unlock_rule):
		errors.append("阶段解锁条件未配置或无效。")
	if unlock_rule in [UnlockRule.KEY, UnlockRule.NORMAL_CLEARED_AND_KEY]:
		if str(key_id).strip_edges().is_empty() or not known_key_ids.has(key_id) or key_count < 1:
			errors.append("钥匙条件必须引用已定义钥匙并指定正数量。")
		if key_use not in [KeyUse.KEEP, KeyUse.CONSUME]:
			errors.append("钥匙条件必须显式选择保留或消费。")
	elif key_id != &"" or key_count != 0 or key_use != KeyUse.NOT_REQUIRED:
		errors.append("非钥匙条件必须明确为 NOT_REQUIRED，且不残留钥匙参数。")
	if not require_card_selection or not require_zombie_preview:
		errors.append("所有阶段无条件强制选卡与僵尸预览。")
	if card_mode != CardMode.CHOOSE_CARDS:
		errors.append("当前卡槽模式与强制选卡不兼容。")
	if max_selected_cards < 1 or max_selected_cards > 15:
		errors.append("当前阶段必须设置1到15个可选卡槽。")
	var wave_count := 0 # 用于子资源的波次边界校验，缺配置仍继续收集其他错误。
	if wave_profile == null:
		errors.append("阶段缺少 WaveProfile。")
	else:
		wave_count = wave_profile.wave_count
		errors.append_array(wave_profile.validate(known_tier_ids))
	if drop_table == null:
		errors.append("阶段缺少独立 DropTable。")
	else:
		errors.append_array(drop_table.validate())
	var encounter_ids: Array[StringName] = [] # 先建立完整目录，允许事件引用列表中稍后的遭遇。
	for encounter: BossEncounterDefinition in boss_encounters: # 不实例化遭遇资源所描述的角色。
		if encounter == null:
			errors.append("阶段包含空 Boss 遭遇。")
			continue
		if encounter_ids.has(encounter.encounter_id):
			errors.append("Boss 遭遇 ID 重复：%s。" % encounter.encounter_id)
		encounter_ids.append(encounter.encounter_id)
		errors.append_array(encounter.validate(wave_count, known_tier_ids))
	var event_ids: Dictionary = {} # 事件 ID 以阶段为作用域。
	for event: StageEventDefinition in events: # 校验参数及引用，不调用事件动作。
		if event == null:
			errors.append("阶段包含空事件。")
			continue
		if event_ids.has(event.event_id):
			errors.append("阶段事件 ID 重复：%s。" % event.event_id)
		event_ids[event.event_id] = true
		errors.append_array(event.validate(wave_count, known_tier_ids, encounter_ids))
	return errors
