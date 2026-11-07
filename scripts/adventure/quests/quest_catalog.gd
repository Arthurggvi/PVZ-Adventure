## 任务静态定义。前置完成和最低等级由 activation_mode 决定全部或任一满足。
extends RefCounted
class_name AdventureQuestCatalog

## 目录展示顺序。
const GROUPS := ["主线任务", "支线任务", "日常任务", "活动任务", "已完成"]
## 稳定 ID 与业务规则；accept_history 仅用于可从现有永久状态恢复的目标。
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
	{"id": "daily_boss", "group": "日常任务", "title": "擒贼先擒王",
	"description": "击败任意一个 BOSS。\n\n每天零点刷新，按本机日期计算。请在刷新前领取奖励。", "objective": "击败任意一个 BOSS",
	"event": "boss_defeated", "target": "", "daily": true, "accept_history": false,
	"requires_completed": [], "min_level": 0, "activation_mode": "all", "count": 1,
	"exp": 5000, "coins": 2000, "unlocks": [], "items": [{"id": "fertilizer_lv3", "count": 1}]},
]

## 返回 [param id] 的独立定义，未知 ID 返回空字典。
static func definition(id: String) -> Dictionary:
	for task: Dictionary in TASKS: # 静态目录唯一 ID。
		if task.id == id:
			return task.duplicate(true)
	return {}
