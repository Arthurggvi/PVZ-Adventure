## 寒冰射手四阶转职书；ID 用于背包物品和永久转职记录。
extends RefCounted

## 每阶两个互斥选项；技能的可调数值随出战选择一并冻结。
const BOOKS: Dictionary = {
	"promotion_snow_pea_cold_extract": {
		"title": "冷萃", "summary": "直击在周围溅射50%的豌豆伤害，溅射目标也受到同种减速。", "plant_type": 6, "tier": 1,
		"effects": [{"kind": "snow_pea_cold_extract", "damage_factor": 0.5, "width_cells": 1.6}]},
	"promotion_snow_pea_brittleness": {
		"title": "脆性", "summary": "命中已被寒冷减速的僵尸，叠加10层脆弱，最多100层。每层使其受到的伤害增加1%。", "plant_type": 6, "tier": 1,
		"effects": [{"kind": "snow_pea_brittleness", "stacks": 10}]},
	"promotion_snow_pea_winter": {
		"title": "凛冬", "summary": "有效命中附加2点冻结值。", "plant_type": 6, "tier": 2,
		"effects": [{"kind": "snow_pea_winter", "points": 2}]},
	"promotion_snow_pea_corridor": {
		"title": "回廊", "summary": "豌豆穿过命中前已经被寒冷减速的僵尸，每颗豌豆对同一目标只命中一次。", "plant_type": 6, "tier": 2,
		"effects": [{"kind": "snow_pea_corridor"}]},
	"promotion_snow_pea_deep_cold": {
		"title": "深寒", "summary": "发射深蓝豌豆，施加抗火减速和0.2秒抗火冻结。未冻结的目标开始冻结时受到20点真实伤害。", "plant_type": 6, "tier": 3,
		"effects": [{"kind": "snow_pea_deep_cold", "seconds": 0.2, "damage": 20}]},
	"promotion_snow_pea_torment": {
		"title": "酷刑", "summary": "每颗豌豆命中的首个僵尸沿路留下5秒冰痕。接触冰痕每秒受到一次该来源的减速相关词条。", "plant_type": 6, "tier": 3,
		"effects": [{"kind": "snow_pea_torment", "seconds": 5.0}]},
	"promotion_snow_pea_skadi": {
		"title": "斯卡蒂", "summary": "致死命中留下可受击冰雕。冰雕受伤时碎裂成16枚等角穿透棱锥，各继承豌豆伤害与词条，额外附加5点冻结值。", "plant_type": 6, "tier": 4,
		"effects": [{"kind": "snow_pea_skadi", "prism_count": 16, "prism_points": 5}]},
	"promotion_snow_pea_chione": {
		"title": "喀俄涅", "summary": "每第5次原生射击吹起暴雪，将本行可击退的敌方僵尸推后2格，随后加射5颗继承词条的豌豆。", "plant_type": 6, "tier": 4,
		"effects": [{"kind": "snow_pea_chione", "period": 5, "cells": 2.0, "shots": 5, "spacing": 0.10}]},
}
