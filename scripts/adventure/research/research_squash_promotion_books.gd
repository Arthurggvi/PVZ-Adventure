## 窝瓜四阶转职书。费用和冷却由现有出战卡结算，压砸规则由单株快照冻结。
extends RefCounted

## 同阶互斥，技能顺序固定为一至四转。
const BOOKS: Dictionary = {
	"promotion_squash_cheap": {
		"title": "廉价作物", "summary": "阳光消耗降低25，每击杀一个僵尸掉落25阳光。", "plant_type": 18, "tier": 1,
		"effects": [{"kind": "stat", "stat": "sun_cost", "flat": -25}, {"kind": "squash_cheap", "sun": 25}]},
	"promotion_squash_rapid": {
		"title": "急速支援", "summary": "卡片冷却减半。", "plant_type": 18, "tier": 1,
		"effects": [{"kind": "stat", "stat": "cooldown", "final_multiplier": 0.5}]},
	"promotion_squash_shock": {
		"title": "震撼", "summary": "砸中僵尸时，使落点周围3×3的僵尸抛飞1.5格并眩晕2秒。", "plant_type": 18, "tier": 2,
		"effects": [{"kind": "squash_shock", "radius": 1, "distance": 1.5, "stun": 2.0}]},
	"promotion_squash_resentment": {
		"title": "愤恨", "summary": "本轮没有击杀僵尸且未有效命中僵王时，在原格复制自身，可继续触发愤恨。", "plant_type": 18, "tier": 2,
		"effects": [{"kind": "squash_resentment"}]},
	"promotion_squash_king": {
		"title": "窝瓜王", "summary": "召来6个半伤窝瓜，依次落在周围3×3内。优先有敌人的格，无目标则随机。每次对僵王最多造成基础压砸伤害的30%。", "plant_type": 18, "tier": 3,
		"effects": [{"kind": "squash_king", "count": 6, "fraction": 0.5, "boss_cap": 0.3}]},
	"promotion_squash_training": {
		"title": "无氧训练", "summary": "每次放置为下一株同卡窝瓜增加20%伤害，最高为300%。愤恨生成的窝瓜也计入。", "plant_type": 18, "tier": 3,
		"effects": [{"kind": "squash_training", "gain": 20, "cap": 300}]},
	"promotion_squash_quake": {
		"title": "地震", "summary": "一轮攻击后，使周围5×5的僵尸抛飞1格并眩晕3秒，可与震撼叠加。", "plant_type": 18, "tier": 4,
		"effects": [{"kind": "squash_quake", "radius": 2, "distance": 1.0, "stun": 3.0}]},
	"promotion_squash_leader": {
		"title": "地表最强智慧与肌肉并存的植物领袖", "summary": "一轮攻击后释放3×3爆炸，基础伤害1000，享受等阶伤害加成，对僵王最多造成300伤害。", "plant_type": 18, "tier": 4,
		"effects": [{"kind": "squash_leader", "radius": 1, "damage": 1000, "boss_cap": 0.3}]},
}
