## 缠绕海草的四阶转职；每阶两个互斥选项，费用沿用公共属性。
extends RefCounted

## 冻结效果供书目、种植事务与实际拖拽击杀共用。
const BOOKS: Dictionary = {
	"promotion_tanglekelp_cheap_crop": {
		"title": "廉价作物", "summary": "种植少花25阳光。", "plant_type": 20, "tier": 1,
		"effects": [{"kind": "stat", "stat": "sun_cost", "flat": -25}]},
	"promotion_tanglekelp_siren": {
		"title": "塞壬", "summary": "击杀僵尸时，在原地生成一只同类的魅惑僵尸。", "plant_type": 20, "tier": 1,
		"effects": [{"kind": "tanglekelp_siren"}]},
	"promotion_tanglekelp_slots": {
		"title": "老虎机", "summary": "每击杀一只僵尸，随机掉落25、50、75或100阳光。", "plant_type": 20, "tier": 2,
		"effects": [{"kind": "tanglekelp_slots", "unit": 25, "min_units": 1, "max_units": 4}]},
	"promotion_tanglekelp_parasite": {
		"title": "寄生", "summary": "可种在水域的其他植物上。宿主死亡时，将正在啃食它的水中僵尸拖入水下。", "plant_type": 20, "tier": 2,
		"effects": [{"kind": "tanglekelp_parasite"}]},
	"promotion_tanglekelp_spread": {
		"title": "疯狂海草", "summary": "种植后，在周围3×3范围内的所有可用格子里长出海草。", "plant_type": 20, "tier": 3,
		"effects": [{"kind": "tanglekelp_spread"}]},
	"promotion_tanglekelp_evil_spirit": {
		"title": "恶鬼", "summary": "发动攻击时，将周围3×3范围内的水中僵尸全部拖入水下。", "plant_type": 20, "tier": 3,
		"effects": [{"kind": "tanglekelp_evil_spirit"}]},
	"promotion_tanglekelp_envy_vine": {
		"title": "嫉妒之藤", "summary": "每击杀一只僵尸，将它被击杀前的剩余本体生命转为附近随机一株植物的护甲，上限3000。", "plant_type": 20, "tier": 4,
		"effects": [{"kind": "tanglekelp_envy_vine", "armor_cap": 3000}]},
	"promotion_tanglekelp_greed_vine": {
		"title": "贪婪之藤", "summary": "每击杀一只僵尸，掉落一枚金币。", "plant_type": 20, "tier": 4,
		"effects": [{"kind": "tanglekelp_greed_vine"}]},
}
