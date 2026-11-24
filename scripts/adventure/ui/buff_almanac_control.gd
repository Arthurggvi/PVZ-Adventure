## Buff 图鉴的通用行动控制说明；仅含只读展示数据，不加载战斗场景或施加效果。
extends RefCounted

## 本组条目按固定顺序编排；数值和叠加规则对应每条上方所列的实战实现。
const ENTRIES: Array[Dictionary] = [
	# 实现依据：scripts/adventure/adventure_plant_negative_effects.gd；scripts/adventure/adventure_plant_nullification.gd；scripts/character/zombie/zombie_000_base.gd。
	{
		"buff_id": &"stun", "title": "眩晕",
		"category": "行动控制", "color": Color(0.77, 0.52, 0.31), "symbol": "晕",
		"summary": "短时间暂停行动。普通僵尸使用独立零速状态；植物通过活动封锁暂停自身行为。",
		"stats": {"持续时间": "由来源决定", "首领": "不接受通用眩晕"},
		"effects": [{"title": "规则与边界", "options": {
			"重复施加": "保留较长的剩余时间，不把时长直接相加；恢复时只解除眩晕本身，其他控制继续生效。",
			"植物边界": "植物眩晕仍保留受击和铲除入口，并与其他无效化来源独立存在。负面免疫植物会拒绝统一入口的眩晕。",
		}}],
		"sources": "电击、樱桃炸弹冲击、小喷菇／双发射手变种、部分首领技能。",
		"preview": {"subject": "zombie", "rate": 0, "caption": "眩晕期间暂停行动，到期后恢复；不改变阵营。"},
	},
	# 实现依据：scripts/character/zombie/zombie_000_base.gd；scripts/character/zombie/zombie_013_zamboni.gd；scripts/character/zombie/zombie_014_bobsled.gd；scripts/character/zombie/zombie_025_imp.gd。
	{
		"buff_id": &"butter", "title": "黄油定身",
		"category": "行动控制", "color": Color(0.89, 0.73, 0.26), "symbol": "油",
		"summary": "黄油糊住普通僵尸头部，把黄油速度通道设为零，并显示原生黄油贴图。",
		"stats": {"默认时长": "4秒", "重复命中": "重新开始本次时长"},
		"effects": [{"title": "规则与边界", "options": {
			"独立控制": "到期只解除黄油，不清除冰冻、眩晕或其他速度因素；死亡时移除黄油表现。",
			"物种差异": "冰车和雪橇车不受黄油；被投掷或正在落地的小鬼暂不接受。持杆跳跳先落到地面再停顿。",
		}}],
		"sources": "玉米投手的黄油弹。",
		"preview": {"subject": "zombie", "rate": 0, "caption": "头部出现黄油，原生动作暂停；普通默认持续4秒。"},
	},
	# 实现依据：scripts/adventure/adventure_fear_effect.gd；scripts/character/components/component_move.gd。
	{
		"buff_id": &"fear", "title": "恐惧",
		"category": "行动控制", "color": Color(0.39, 0.37, 0.49), "symbol": "惧",
		"summary": "让普通僵尸向反方向逃跑，并禁用攻击。目标仍属于原来的敌方阵营。",
		"stats": {"移动方向": "反向", "攻击": "暂停", "时长": "由来源决定"},
		"effects": [{"title": "规则与边界", "options": {
			"重复与结束": "保留较长剩余时间，不会因连续命中反复翻转朝向。死亡、魅惑、真正离场或原战局结束时解除。",
			"适用范围": "只作用于具有普通移动组件的僵尸；通用恐惧不支持首领。与寒冷等速度修正独立组合。",
		}}],
		"sources": "大喷菇变异喷涌等恐惧来源。",
		"preview": {"subject": "zombie", "rate": 1, "caption": "敌人掉头逃跑并停攻；敌我阵营没有改变。"},
	},
	# 实现依据：scripts/adventure/adventure_silence_effect.gd；scripts/adventure/adventure_zombie_timed_combat_buff.gd；scripts/adventure/adventure_zombie_timed_speed_boost.gd。
	{
		"buff_id": &"silence", "title": "沉默",
		"category": "行动控制", "color": Color(0.52, 0.55, 0.58), "symbol": "默",
		"summary": "暂时压制僵尸的冒险等阶技能和持续输出，保留基础生命、攻击成长以及原生动作。",
		"stats": {"普通移动／攻击": "保留", "等阶技能": "暂时禁用", "时长": "取较长剩余时间"},
		"effects": [{"title": "规则与边界", "options": {
			"恢复规则": "自身等阶提供的限时增益会遮蔽并暂停剩余计时，解除后继续；已经收到的外部增益按自身规则保留。",
			"首领边界": "首领免疫沉默，原生技能照常执行。",
			"生命周期": "死亡、魅惑、真正离场或原战局结束时清理；恢复不会补发过期事件或重复出生奖励。",
		}}],
		"sources": "大喷菇变异喷涌等沉默来源。",
		"preview": {"subject": "zombie", "rate": 1, "caption": "普通行动继续，等阶技能标记暂时熄灭。"},
	},
	# 实现依据：scripts/adventure/adventure_plant_negative_effects.gd；scripts/character/character_000_base.gd；scripts/character/zombie_boss/z_b_000_base.gd。
	{
		"buff_id": &"charm", "title": "魅惑",
		"category": "阵营变化", "color": Color(0.8, 0.4, 0.71), "symbol": "惑",
		"summary": "调用僵尸的原生魅惑行为，使其转向并按友方身份参与战斗。效果不是限时恐惧。",
		"stats": {"阵营": "转为友方", "通用倒计时": "无"},
		"effects": [{"title": "规则与边界", "options": {
			"免疫与限制": "植物不能通过此入口被魅惑；首领、冰车、雪橇车等保留原生魅惑免疫。物种的特殊行为仍由自身处理。",
			"索敌与命中": "魅惑僵尸无视首领，啃咬和爆炸也会跳过首领。",
			"状态联动": "魅惑会通知既有状态。中毒、灼烧、恐惧、沉默及累积标记等按各自规则清理；部分明确允许保留的无敌仍可持续。",
		}}],
		"sources": "魅惑菇、大喷菇／小喷菇变种、伊芙「极光星弹」的魅惑效果。",
		"preview": {"subject": "zombie", "rate": 1, "caption": "目标转向并改为友军；不同于仍是敌人的恐惧。"},
	},
	# 实现依据：scripts/adventure/adventure_plant_nullification.gd；scripts/main_game_item/ladder.gd。
	{
		"buff_id": &"nullification", "title": "无效化",
		"category": "行动控制", "color": Color(0.34, 0.34, 0.39), "symbol": "封",
		"summary": "把植物变为焦黑状态并封锁活动，停止攻击、生产及其他自身处理；仍可受到伤害或被铲除。",
		"stats": {"作用对象": "植物", "时限": "由来源维持或永久保留"},
		"effects": [{"title": "规则与边界", "options": {
			"多来源": "每个来源独立登记，最后一个可解除来源撤销后才恢复；不会把植物的其他状态一并清空。",
			"持续与净化": "部分梯子会在移除后保留永久无效化。净化可清除全部来源，包括永久来源；负面免疫植物拒绝施加。",
		}}],
		"sources": "高阶扶梯僵尸搭设的无效化梯子。",
		"preview": {"subject": "plant", "rate": 0, "caption": "植物变黑并停用自身能力，仍能承受攻击。"},
	},
	# 实现依据：scripts/adventure/skills/midnight_clockmaker_slow_effect.gd；scripts/adventure/skills/battle_action_slowdown.gd；scripts/character/character_000_base.gd。
	{
		"buff_id": &"action_slowdown", "title": "行动迟滞",
		"category": "行动控制", "color": Color(0.66, 0.54, 0.82), "symbol": "时",
		"summary": "以独立的行动倍率减慢首领和可受控敌方僵尸的动作时钟，并沿共同恢复曲线逐渐恢复。",
		"stats": {"钟表匠起始倍率": "×0.10", "恢复时间": "12战斗秒"},
		"effects": [{"title": "规则与边界", "options": {
			"作用范围": "TMC-112 对首领及其分身生效。效果期间入场的目标共享当前倍率与剩余时长。",
			"叠加与结束": "不同施放来源的行动倍率相乘，并与原生速度因子组合；死亡、转为友军、离场或战局结束时撤销相应来源。",
		}}],
		"sources": "午夜钟表匠「TMC-112」。",
		"preview": {"subject": "zombie", "rate": 0.1, "caption": "起始动作速度仅为10%，随后逐渐恢复；并非冰冻。"},
	},
]
