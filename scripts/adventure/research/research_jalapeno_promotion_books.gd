## 火爆辣椒四阶转职书，由研究室和物品目录共用。
extends RefCounted

## 每阶两个互斥选项；阳光费用沿用公共属性，其余交给原生引爆入口。
const BOOKS: Dictionary = {
	"promotion_jalapeno_cheap_crop": {
		"title": "廉价作物", "summary": "阳光费用降低50，最低降至0。", "plant_type": 21, "tier": 1,
		"effects": [{"kind": "stat", "stat": "sun_cost", "flat": -50}]},
	"promotion_jalapeno_reaper": {
		"title": "死神辣椒", "summary": "每烧死一个僵尸，这张卡少等1秒。", "plant_type": 21, "tier": 1,
		"effects": [{"kind": "jalapeno_reaper"}]},
	"promotion_jalapeno_wildfire": {
		"title": "燎原", "summary": "燃烧蔓延至所在行和上下相邻行。", "plant_type": 21, "tier": 2,
		"effects": [{"kind": "jalapeno_wildfire"}]},
	"promotion_jalapeno_fire_tongue": {
		"title": "火舌", "summary": "沿所在行和列形成十字火焰。", "plant_type": 21, "tier": 2,
		"effects": [{"kind": "jalapeno_fire_tongue"}]},
	"promotion_jalapeno_combustion": {
		"title": "爆燃", "summary": "燃烧后留下5秒地火，触碰火焰的僵尸每0.5秒受40点伤害并灼烧2秒；被烧死者引燃附近敌人。", "plant_type": 21, "tier": 3,
		"effects": [{"kind": "jalapeno_combustion"}]},
	"promotion_jalapeno_purge": {
		"title": "涤荡", "summary": "燃烧伤害翻倍。对僵王的单次爆炸最高为基础伤害的1.5倍。", "plant_type": 21, "tier": 3,
		"effects": [{"kind": "jalapeno_purge"}]},
	"promotion_jalapeno_inferno": {
		"title": "业火", "summary": "所有伤害加成计算后，再将伤害翻倍。对僵王的单次爆炸最高为基础伤害的1.5倍。", "plant_type": 21, "tier": 4,
		"effects": [{"kind": "jalapeno_inferno"}]},
	"promotion_jalapeno_nirvana": {
		"title": "涅槃", "summary": "范围内的友方植物恢复等同本次爆炸伤害的生命，清除负面效果并无敌2秒。", "plant_type": 21, "tier": 4,
		"effects": [{"kind": "jalapeno_nirvana"}]},
}
