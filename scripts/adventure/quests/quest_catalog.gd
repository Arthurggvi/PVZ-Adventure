## 任务静态定义。前置完成和最低等级由 activation_mode 决定全部或任一满足。
extends RefCounted
class_name AdventureQuestCatalog

## 目录展示顺序。
const GROUPS := ["主线任务", "支线任务", "日常任务", "活动任务", "已完成"]
## 作者主页是活动信中唯一允许跳转到浏览器的链接。
const AUTHOR_PROFILE_URL := "https://space.bilibili.com/487448115"
## 活动信使用富文本强调提示、保留作者主页并为祝福语添加流动彩虹色。
const THANK_YOU_LETTER := """[font_size=34][color=#a4452c]感谢你下载这个游戏！[/color][/font_size]
目前游戏仍处于测试阶段，由于作者只会 [color=#24685b]vibe coding[/color]，
如果你遇到任何问题，欢迎及时向我反馈！
当前版本尚未做任何平衡调整，未来可能会对部分内容进行平衡。

我是士兵02，B 站 [url=%s][color=#185f8c]%s[/color][/url]
偶尔直播展示开发流程。
[color=#24685b]这是完全免费开源的二创作品[/color]，如果你是付费下载，请立刻举报商家！ [color=#a4452c](≧▽≦)[/color]
[center][font_size=37][outline_size=6][outline_color=#3b2d31][rainbow freq=1.0 sat=0.70 val=1.0 speed=0.35]祝你游玩愉快！！[/rainbow][/outline_color][/outline_size][/font_size][/center]""" % [AUTHOR_PROFILE_URL, AUTHOR_PROFILE_URL]
## 普通主线和噩梦清场任务共用的强化道具奖励。
const ENHANCEMENT_REWARDS := [{"id": "fertilizer_lv2", "count": 2}, {"id": "growth_agent_lv2", "count": 2}]
## 指定 Boss 击败任务共用的强化道具奖励。
const BOSS_ENHANCEMENT_REWARDS := [{"id": "fertilizer_lv2", "count": 3}, {"id": "growth_agent_lv2", "count": 3}]
## 收集目标的库存 ID，以及可证明该钥匙已使用的神殿通关记录。
const EDGAR_KEYS := {
	"zombie_island.edgar_temple.nightmare_key": "zombie_island.edgar_temple/nightmare",
	"zombie_island.edgar_temple.nightmare_key_lower": "zombie_island.edgar_temple/terminal",
}
## 每日战斗击杀目标，供任务目录和高频计数共用。
const FRONTLINE_SWEEP := {"id": "daily_frontline_sweep", "group": "日常任务", "title": "前线扫荡",
	"description": "击杀 1000 只僵尸。\n\n每天零点刷新，按本机日期计算。请在刷新前领取奖励。",
	"objective": "击杀 1000 只僵尸", "event": "zombie_defeated", "target": "", "daily": true, "accept_history": false,
	"requires_completed": [], "min_level": 0, "activation_mode": "all", "count": 1000,
	"exp": 2000, "coins": 20000, "unlocks": [], "items": []}
## 稳定 ID 与业务规则；accept_history 仅用于可从现有永久状态恢复的目标。
## 空 event 表示根据当前状态判断完成；completion_level 可指定目标等级。
## required_plant_type 要求在本次通关的战斗中实际使用该植物卡。
## adventure_boss_defeated 匹配指定遭遇的击败；history_claim 可补记能证明该击败的旧首通记录。
## additional_equipment_rewards 每个 ID 发放一件独立实例，也开放给已领取原奖励的档案补领一次。
const TASKS: Array[Dictionary] = [
	{"id": "first_expedition", "group": "主线任务", "title": "初次远征",
	"description": "通过草坪的普通关卡。\n\n领取奖励后解锁研究室功能，并开启主线任务「初次制卡」。", "objective": "通过草坪的普通关卡",
	"event": "stage_cleared", "target": "zombie_island.lawn/normal", "daily": false, "accept_history": true,
	"requires_completed": [], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 500, "coins": 2000, "unlocks": ["research"],
	"items": [{"id": "recipe_wall_nut", "count": 1}, {"id": "unsaturated_fat", "count": 1}, {"id": "nut_fragments", "count": 1}]},
	{"id": "first_craft", "group": "主线任务", "title": "初次制卡",
	"description": "在研究室中制作一张卡片。", "objective": "在研究室中制作一张卡片",
	"event": "card_crafted", "target": "", "daily": false, "accept_history": false,
	"requires_completed": [], "requires_claimed": ["first_expedition"], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 200, "coins": 2000, "unlocks": [],
	"items": [{"id": "recipe_potato_mine", "count": 1}, {"id": "plant_starch", "count": 1}, {"id": "explosive_seed", "count": 1}, {"id": "plant_fiber", "count": 1}]},
	{"id": "solid_defense", "group": "主线任务", "title": "坚固防线",
	"description": "在没落营地的普通阶段种下至少一株坚果墙，并赢得同一场战斗。",
	"objective": "种下坚果墙并通关没落营地普通阶段",
	"event": "stage_cleared", "target": "zombie_island.fallen_camp/normal",
	"required_plant_type": CharacterRegistry.PlantType.P004WallNut, "daily": false, "accept_history": false,
	"requires_completed": ["first_craft"], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 1000, "coins": 2000, "unlocks": [], "items": ENHANCEMENT_REWARDS},
	{"id": "dusk_approaches", "group": "主线任务", "title": "黄昏降至",
	"description": "通关墓地上游的普通阶段。", "objective": "通关墓地上游普通阶段",
	"event": "stage_cleared", "target": "zombie_island.grave_upstream/normal", "daily": false, "accept_history": true,
	"requires_completed": ["solid_defense"], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 1000, "coins": 2000, "unlocks": [], "items": ENHANCEMENT_REWARDS},
	{"id": "silent_hour", "group": "主线任务", "title": "寂静时刻",
	"description": "通关墓地下游的普通阶段。", "objective": "通关墓地下游普通阶段",
	"event": "stage_cleared", "target": "zombie_island.grave_downstream/normal", "daily": false, "accept_history": true,
	"requires_completed": ["dusk_approaches"], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 1000, "coins": 2000, "unlocks": [], "items": ENHANCEMENT_REWARDS + [
		{"id": "recipe_p017", "count": 1}, {"id": "aquatic_fiber", "count": 1}, {"id": "plant_fiber", "count": 1}]},
	{"id": "strike_at_the_heart", "group": "主线任务", "title": "直捣黄龙",
	"description": "通关埃德加神殿的普通阶段。领奖后听戴夫说说埃德加的线索，谈完即可解锁城镇商店。",
	"objective": "通关埃德加神殿普通阶段",
	"event": "stage_cleared", "target": "zombie_island.edgar_temple/normal", "daily": false, "accept_history": true,
	"requires_completed": ["silent_hour"], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 2000, "coins": 5000, "unlocks": ["shop"], "unlock_after_step": "shop_dave",
	"items": [{"id": "lawn_nightmare_key", "count": 1}, {"id": "zombie_island.fallen_camp.nightmare_key", "count": 1},
		{"id": "zombie_island.grave_upstream.nightmare_key", "count": 1},
		{"id": "zombie_island.grave_downstream.nightmare_key", "count": 1}]},
	{"id": "unravel_the_clues", "group": "主线任务", "title": "抽丝剥茧",
	"description": "收集埃德加钥匙（上）和埃德加钥匙（下）。\n\n分别击败没落营地噩梦的黑将军与墓地下游噩梦的白爵士，即可在胜利结算中获得。",
	"objective": "收集埃德加钥匙（上）和埃德加钥匙（下）",
	"event": "", "target": "", "daily": false, "accept_history": false, "collect_items": EDGAR_KEYS,
	"requires_completed": ["strike_at_the_heart"], "min_level": 0, "activation_mode": "all", "count": 2,
	"exp": 2000, "coins": 5000, "unlocks": [], "items": []},
	{"id": "hundred_night_battle", "group": "主线任务", "title": "百夜鏖战",
	"description": "使用埃德加钥匙（上）进入埃德加神殿的噩梦阶段，通关后使用埃德加钥匙（下）进入终末阶段，击败僵王博士。",
	"objective": "击败埃德加神殿终末阶段的僵王博士",
	"event": "adventure_boss_defeated", "target": "zombie_island.edgar_temple.terminal.doctor",
	"daily": false, "accept_history": false,
	"requires_completed": ["unravel_the_clues"], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 5000, "coins": 10000, "unlocks": [], "items": []},
	{"id": "tempered_card", "group": "支线任务", "title": "千锤百炼",
	"description": "在研究室成功将任意一张卡片从 3 星强化到 4 星。", "objective": "成功强化出一张 4 星卡片",
	"event": "card_enhanced", "target": "4", "daily": false, "accept_history": false,
	"requires_completed": ["solid_defense"], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 1000, "coins": 2000, "unlocks": ["library"], "unlock_on_completion": true,
	"items": [{"id": "fertilizer_lv2", "count": 3},
		{"id": "growth_agent_lv2", "count": 3}, {"id": "seedling_pot", "count": 3}]},
	{"id": "rising_adventurer", "group": "支线任务", "title": "新晋达人",
	"description": "将玩家等级提升至 5 级。", "objective": "玩家等级达到 5 级",
	"event": "", "target": "", "daily": false, "accept_history": false,
	"required_normal_clear": &"zombie_island.fallen_camp", "completion_level": 5,
	"requires_completed": [], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 0, "coins": 5000, "unlocks": [], "items": [], "equipment_reward": "adventurer_badge"},
	{"id": "peril_on_the_lawn", "group": "支线任务", "title": "危机四伏",
	"description": "使用草坪的噩梦钥匙进入噩梦阶段并通关。", "objective": "通关草坪噩梦阶段",
	"event": "stage_cleared", "target": "zombie_island.lawn/nightmare", "daily": false, "accept_history": true,
	"requires_completed": ["strike_at_the_heart"], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 1000, "coins": 2000, "unlocks": [], "items": ENHANCEMENT_REWARDS},
	{"id": "besieged_camp", "group": "支线任务", "title": "四面楚歌",
	"description": "使用没落营地的噩梦钥匙进入噩梦阶段，击败黑将军。", "objective": "击败没落营地噩梦阶段的黑将军",
	"event": "adventure_boss_defeated", "target": "zombie_island.fallen_camp.nightmare.black_general",
	"daily": false, "accept_history": true,
	"history_claim": "first_clear/zombie_island.fallen_camp.nightmare",
	"requires_completed": ["strike_at_the_heart"], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 2000, "coins": 5000, "unlocks": [], "items": BOSS_ENHANCEMENT_REWARDS},
	{"id": "graveyard_sunset", "group": "支线任务", "title": "斜阳日下",
	"description": "使用墓地上游的噩梦钥匙进入噩梦阶段并通关。", "objective": "通关墓地上游噩梦阶段",
	"event": "stage_cleared", "target": "zombie_island.grave_upstream/nightmare", "daily": false, "accept_history": true,
	"requires_completed": ["strike_at_the_heart"], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 1000, "coins": 2000, "unlocks": [], "items": ENHANCEMENT_REWARDS},
	{"id": "return_of_the_dead", "group": "支线任务", "title": "亡者归来",
	"description": "使用墓地下游的噩梦钥匙进入噩梦阶段，击败白爵士。", "objective": "击败墓地下游噩梦阶段的白爵士",
	"event": "adventure_boss_defeated", "target": "zombie_island.grave_downstream.white_duke",
	"daily": false, "accept_history": true,
	"history_claim": "first_clear/zombie_island.grave_downstream.nightmare",
	"requires_completed": ["strike_at_the_heart"], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 2000, "coins": 5000, "unlocks": [], "items": BOSS_ENHANCEMENT_REWARDS},
	{"id": "daily_boss", "group": "日常任务", "title": "擒贼先擒王",
	"description": "击败任意一个 BOSS。\n\n每天零点刷新，按本机日期计算。请在刷新前领取奖励。", "objective": "击败任意一个 BOSS",
	"event": "boss_defeated", "target": "", "daily": true, "accept_history": false,
	"requires_completed": [], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 5000, "coins": 2000, "unlocks": [], "items": [{"id": "fertilizer_lv3", "count": 1},
		{"id": "growth_agent_lv3", "count": 1}, {"id": "seedling_pot", "count": 1}]},
	FRONTLINE_SWEEP,
	{"id": "thank_you", "group": "活动任务", "title": "感谢有你！", "description": THANK_YOU_LETTER,
	"letter": true, "event": "", "target": "", "daily": false, "accept_history": false,
	"requires_completed": ["first_expedition"], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 0, "coins": 0, "unlocks": [], "items": [], "equipment_reward": "deepseek_whale",
	"equipment_label": "DeepSeek 鲸鱼娘时装", "additional_equipment_rewards": ["sun_collector", "drop_collector"]},
]

## 返回 [param id] 的独立定义，未知 ID 返回空字典。
static func definition(id: String) -> Dictionary:
	for task: Dictionary in TASKS: # 静态目录唯一 ID。
		if task.id == id:
			return task.duplicate(true)
	return {}
