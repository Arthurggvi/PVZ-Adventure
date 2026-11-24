## 仙人掌的四阶选择；各技能只影响冻结了对应书页的植株及其弹体。
extends RefCounted

## 一至四转各有两本技能书。
const BOOKS: Dictionary = {
	"promotion_cactus_guided": {
		"title": "制导", "summary": "低形态射击攻速提高50%；高形态发射可跟踪空中僵尸的尖刺。",
		"plant_type": 27, "tier": 1, "effects": [{"kind": "cactus_guided"}]},
	"promotion_cactus_pierce": {
		"title": "贯穿", "summary": "尖刺命中后继续飞行，碰到二类防具时停止。",
		"plant_type": 27, "tier": 1, "effects": [{"kind": "cactus_pierce"}]},
	"promotion_cactus_wound": {
		"title": "创伤", "summary": "攻速提高20%。紫色尖刺在命中后叠加20层创伤，使敌人之后每次承伤增加等同于创伤层数的伤害。",
		"plant_type": 27, "tier": 2, "effects": [{"kind": "cactus_wound", "attack_rate": 0.2}]},
	"promotion_cactus_shock": {
		"title": "感电", "summary": "攻速提高20%。蓝色尖刺使敌人感电，再次承伤后向附近僵尸放出至多跳跃3次的闪电链。每0.3秒最多触发一次。",
		"plant_type": 27, "tier": 2, "effects": [{"kind": "cactus_shock", "attack_rate": 0.2}]},
	"promotion_cactus_flood": {
		"title": "泛滥", "summary": "攻速提高20%。被命中过的僵尸死亡时向四周射出一圈尖刺，将自身的创伤层数附加给命中的僵尸。",
		"plant_type": 27, "tier": 3, "effects": [{"kind": "cactus_flood", "attack_rate": 0.2}]},
	"promotion_cactus_thunder": {
		"title": "惊雷", "summary": "攻速提高20%。尖刺命中叠加1层惊雷，满5层时向目标所在格落雷，对格内僵尸造成1800点伤害。",
		"plant_type": 27, "tier": 3, "effects": [{"kind": "cactus_thunder", "attack_rate": 0.2}]},
	"promotion_cactus_burst": {
		"title": "突破", "summary": "每次攻击连续发射5颗尖刺。",
		"plant_type": 27, "tier": 4, "effects": [{"kind": "cactus_burst"}]},
	"promotion_cactus_scatter": {
		"title": "散射", "summary": "每次完成3轮攻击后，下次攻击在前方60°扇形内散射10颗尖刺。",
		"plant_type": 27, "tier": 4, "effects": [{"kind": "cactus_scatter"}]},
}
