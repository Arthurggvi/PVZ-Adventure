## 睡莲四阶转职书；选卡容量、承托和扩散统一使用冻结配方。
extends RefCounted

## 睡莲沿用物种17，每阶两种选择互斥。
const BOOKS: Dictionary = {
	"promotion_lily_lightweight": {
		"title": "轻装上阵", "summary": "种植少花25阳光。", "plant_type": 17, "tier": 1,
		"effects": [{"kind": "stat", "stat": "sun_cost", "flat": -25}]},
	"promotion_lily_vitality": {
		"title": "生命强化", "summary": "最大生命变为原来的3倍。", "plant_type": 17, "tier": 1,
		"effects": [{"kind": "stat", "stat": "max_health", "final_multiplier": 3.0}]},
	"promotion_lily_spread": {
		"title": "浪打浮萍", "summary": "种下时，在周围九宫格的可用水面铺开睡莲。", "plant_type": 17, "tier": 2,
		"effects": [{"kind": "lily_spread"}]},
	"promotion_lily_guardian": {
		"title": "护花使者", "summary": "每5秒治疗承托的植物，治疗量为睡莲最大生命的10%。", "plant_type": 17, "tier": 2,
		"effects": [{"kind": "lily_heal", "interval_seconds": 5.0, "health_fraction": 0.1}]},
	"promotion_lily_portable": {
		"title": "便携睡莲", "summary": "选入出战阵容时，不占用选卡名额。", "plant_type": 17, "tier": 3,
		"effects": [{"kind": "stat", "stat": "selection_slots", "fixed": 0.0}]},
	"promotion_lily_veteran": {
		"title": "百战不殆", "summary": "每5秒为承托的植物增加护甲，数值为睡莲最大生命的10%。", "plant_type": 17, "tier": 3,
		"effects": [{"kind": "lily_armor", "interval_seconds": 5.0, "health_fraction": 0.1}]},
	"promotion_lily_torrent": {
		"title": "滔滔不绝", "summary": "种植冷却固定为1秒。", "plant_type": 17, "tier": 4,
		"effects": [{"kind": "stat", "stat": "cooldown", "fixed": 1.0}]},
	"promotion_lily_undying": {
		"title": "不灭", "summary": "在其他加成结算后，最大生命再翻一倍。", "plant_type": 17, "tier": 4,
		"effects": [{"kind": "stat", "stat": "max_health", "final_multiplier": 2.0}]},
}
