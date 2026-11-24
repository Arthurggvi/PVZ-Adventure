## 玉米投手的八本书以正式 ID 交给库存、研究和冻结卡。
extends RefCounted

## 完整的常规数值与离手事件。
const BOOKS := {
	"promotion_corn_popcap": {"title": "PopCap", "plant_type": 35, "tier": 1,
		"summary": "攻速+30%。戴上PopCap周边帽。每次粒弹齐射追加4粒，玉米粒伤害+50%。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.30}, {"kind": "corn_popcap"}]},
	"promotion_corn_slippery": {"title": "小心地滑", "plant_type": 35, "tier": 1,
		"summary": "攻速+30%。每次攻击有30%概率额外投出一块黄油。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.30}, {"kind": "corn_slippery"}]},
	"promotion_corn_airraid": {"title": "空袭", "plant_type": 35, "tier": 2,
		"summary": "攻速+20%。每粒玉米改为朝天发射，独立锁定随机僵尸，在落点3×3内打击6次。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.20}, {"kind": "corn_airraid"}]},
	"promotion_corn_butter_day": {"title": "黄油日", "plant_type": 35, "tier": 2,
		"summary": "攻速+20%。攻击范围扩为本行和相邻两行，黄油对落点3×3的僵尸施加定身。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.20}, {"kind": "corn_butter_day"}]},
	"promotion_corn_poison": {"title": "谢谢惠顾", "plant_type": 35, "tier": 3,
		"summary": "攻速+20%。每次玉米粒命中叠加1%玉米中毒，每秒按总比例消耗目标最大本体生命。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.20}, {"kind": "corn_poison"}]},
	"promotion_corn_gambler": {"title": "赌徒", "plant_type": 35, "tier": 3,
		"summary": "攻速+20%。每投一粒玉米，后续攻速与伤害各提高40%。黄油出手清空层数，定身延长1.5秒。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.20}, {"kind": "corn_gambler"}]},
	"promotion_corn_green": {"title": "绿色食品", "plant_type": 35, "tier": 4,
		"summary": "攻速+50%，玉米粒伤害+50%。只投玉米粒，每次粒弹齐射追加2粒。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.50}, {"kind": "corn_green"}]},
	"promotion_corn_genetic": {"title": "转基因", "plant_type": 35, "tier": 4,
		"summary": "攻速-20%。每块黄油有30%概率转化成玉米炮，对落点3×3造成1200点爆炸伤害。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": -0.20}, {"kind": "corn_genetic"}]},
}
