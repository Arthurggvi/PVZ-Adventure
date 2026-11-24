## 杨桃的四阶技能，普通攻击才发出额外五向齐射和明星。
extends RefCounted

## 流光用同一个贯穿编号校验研究、旧存档和出战。
const PIERCE_ID: String = "promotion_starfruit_pierce"

## 权威物品和出战规则。
const BOOKS: Dictionary = {
	"promotion_starfruit_lurk": {
		"title": "蛰伏", "summary": "攻速提高20%。僵尸会无视杨桃，经过的载具仍能将其碾压。",
		"plant_type": 30, "tier": 1, "effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.2}, {"kind": "starfruit_lurk"}]},
	"promotion_starfruit_aim": {
		"title": "瞄准", "summary": "伤害提高20%。新星弹飞行0.2秒后锁定最近的地面敌人并转向。",
		"plant_type": 30, "tier": 1, "effects": [{"kind": "stat", "stat": "damage", "percent": 0.2}, {"kind": "starfruit_aim"}]},
	"promotion_starfruit_stellar": {
		"title": "恒星", "summary": "攻速提高20%。每轮普通攻击在五个方向的间隙发出紫星，命中眩晕0.2秒并轻微击退。",
		"plant_type": 30, "tier": 2, "effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.2}, {"kind": "starfruit_stellar"}]},
	PIERCE_ID: {
		"title": "贯穿", "summary": "伤害提高50%。普通星弹穿过敌人，命中施加30%劣化。",
		"plant_type": 30, "tier": 2, "effects": [{"kind": "stat", "stat": "damage", "percent": 0.5}, {"kind": "starfruit_pierce"}]},
	"promotion_starfruit_comet": {
		"title": "彗星", "summary": "攻速提高20%。每轮普通攻击沿五个原方向发出蓝星，命中累积2点冻结值。",
		"plant_type": 30, "tier": 3, "effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.2}, {"kind": "starfruit_comet"}]},
	"promotion_starfruit_refract": {
		"title": "折射", "summary": "伤害提高50%。被本株星弹命中的僵尸死亡时向四周溅出一圈普通星弹。",
		"plant_type": 30, "tier": 3, "effects": [{"kind": "stat", "stat": "damage", "percent": 0.5}, {"kind": "starfruit_refract"}]},
	"promotion_starfruit_celebrity": {
		"title": "明星", "summary": "攻速提高20%。每三次普通攻击选中随机僵尸，召来巨星在落点格造成600伤害，并炸出两圈红星，命中累积1点引爆值。",
		"plant_type": 30, "tier": 4, "effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.2}, {"kind": "starfruit_celebrity"}]},
	"promotion_starfruit_stream": {
		"title": "流光", "summary": "伤害减半。贯穿的普通星弹在与敌人重叠时按30帧每秒结算伤害。需要二转贯穿。",
		"plant_type": 30, "tier": 4, "requires": PIERCE_ID,
		"effects": [{"kind": "stat", "stat": "damage", "final_multiplier": 0.5}, {"kind": "starfruit_stream"}]},
}
