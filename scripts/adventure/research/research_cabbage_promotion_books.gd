## 卷心菜四阶书目与实际投手共用稳定事件。
extends RefCounted

## 背包、图书馆和研究室使用这八个正式编号。
const BOOKS := {
	"promotion_cabbage_gold": {"title": "连投", "plant_type": 33, "tier": 1,
		"summary": "攻速+30%。每次投掷有30%概率投出金色卷心菜，对落点一格造成双倍伤害。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.30}, {"kind": "cabbage_gold"}]},
	"promotion_cabbage_triple": {"title": "重伤", "plant_type": 33, "tier": 1,
		"summary": "攻速+30%。每次攻击有50%概率向主目标连续投掷三次。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.30}, {"kind": "cabbage_triple"}]},
	"promotion_cabbage_hell": {"title": "地狱棒球", "plant_type": 33, "tier": 2,
		"summary": "攻速+20%。每次投掷有30%概率将卷心菜染红，直击施加3秒灼烧和1.5点引爆值。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.20}, {"kind": "cabbage_hell"}]},
	"promotion_cabbage_split": {"title": "裂叶", "plant_type": 33, "tier": 2,
		"summary": "攻速+20%。每次攻击在本行及相邻行额外锁定1至5个不同敌人。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.20}, {"kind": "cabbage_split"}]},
	"promotion_cabbage_homerun": {"title": "全垒打", "plant_type": 33, "tier": 3,
		"summary": "攻速+20%。每次投掷有30%概率投出巨型卷心菜，落点3×3内僵尸眩晕1秒并被抛飞一格。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.20}, {"kind": "cabbage_homerun"}]},
	"promotion_cabbage_again": {"title": "再来", "plant_type": 33, "tier": 3,
		"summary": "攻速+20%。每次原定投掷有50%概率紧接着补投一次。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.20}, {"kind": "cabbage_again"}]},
	"promotion_cabbage_black": {"title": "好日子", "plant_type": 33, "tier": 4,
		"summary": "攻速+20%。每次投掷有30%概率投出黑色卷心菜，落点3×3造成600点基础爆炸伤害，僵王至多承伤300点。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.20}, {"kind": "cabbage_black"}]},
	"promotion_cabbage_two_hundred": {"title": "200%", "plant_type": 33, "tier": 4,
		"summary": "攻速-30%。特殊卷心菜的基础伤害变为三倍，并向落点周围溅射。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": -0.30}, {"kind": "cabbage_two_hundred"}]},
}
