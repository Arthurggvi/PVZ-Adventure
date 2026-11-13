## 阳光菇四阶转职书；玩家说明与冻结执行参数使用同一目录。
extends RefCounted

## 植物编号沿用正式注册表的阳光菇类型10；每阶只选择一条路线。
const BOOKS: Dictionary = {
	"promotion_sunshroom_day_patience": {
		"title": "白昼耐性", "summary": "白天也能保持清醒，正常生长并生产阳光。", "plant_type": 10, "tier": 1,
		"effects": [{"kind": "sunshroom_day_awake"}]},
	"promotion_sunshroom_tidal_energy": {
		"title": "潮汐能", "summary": "长大所需的时间缩短一半。", "plant_type": 10, "tier": 1,
		"effects": [{"kind": "stat", "stat": "growth_time", "percent": -0.5}]},
	"promotion_sunshroom_metabolism": {
		"title": "代谢强化", "summary": "幼体与成年时产出的阳光价值提高50%。", "plant_type": 10, "tier": 2,
		"effects": [{"kind": "stat", "stat": "sun_value", "percent": 0.5}]},
	"promotion_sunshroom_buy_one": {
		"title": "买一赠一", "summary": "种下后立即恢复本卡冷却，下次使用少花25阳光。优惠续种不再触发此效果。", "plant_type": 10, "tier": 2,
		"effects": [{"kind": "sunshroom_buy_one", "discount": 25}]},
	"promotion_sunshroom_spore_spread": {
		"title": "孢子扩散", "summary": "长大时，在上下左右各三格内长出不占种植位的同源幼菇，每格至多保留一株扩散菇。", "plant_type": 10, "tier": 3,
		"effects": [{"kind": "sunshroom_spore_spread", "radius": 3}]},
	"promotion_sunshroom_moonlight": {
		"title": "月光蔓延", "summary": "使自身及周围一圈的蘑菇保持清醒，种下时立即唤醒它们。", "plant_type": 10, "tier": 3,
		"effects": [{"kind": "sunshroom_moonlight"}]},
	"promotion_sunshroom_hive_mind": {
		"title": "蜂群思维", "summary": "每次长大时，卡槽中所有卡片的剩余冷却减半。", "plant_type": 10, "tier": 4,
		"effects": [{"kind": "sunshroom_hive_mind"}]},
	"promotion_sunshroom_savings": {
		"title": "储蓄金", "summary": "每次产阳光时存下等额储蓄，死亡时一次释放，最多储蓄500阳光。", "plant_type": 10, "tier": 4,
		"effects": [{"kind": "sunshroom_savings", "cap": 500}]},
}
