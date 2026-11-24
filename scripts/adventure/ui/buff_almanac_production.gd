## Buff 图鉴的恢复、生产与战场状态说明；仅含只读展示数据，不加载战斗场景或施加效果。
extends RefCounted

## 本组条目按固定顺序编排；数值和叠加规则对应每条上方所列的实战实现。
const ENTRIES: Array[Dictionary] = [
	# 实现依据：scripts/character/components/hp_component/component_hp.gd；scripts/adventure/research/adventure_wallnut_promotion_effects.gd；scripts/adventure/research/adventure_lily_promotion_effects.gd；scripts/adventure/adventure_zombie_jackson_command.gd。
	{
		"buff_id": &"regeneration", "title": "持续恢复",
		"category": "恢复增益", "color": Color(0.41, 0.75, 0.52), "symbol": "愈",
		"summary": "按来源自己的周期恢复本体生命，最多恢复到当前最大生命，不会复活已死亡目标，也不会自动补满临时护甲。",
		"stats": {"恢复量／周期": "由来源分别决定", "坚果不屈示例": "未受本体伤害满1秒后回复5%"},
		"effects": [{"title": "规则与边界", "options": {
			"坚果节拍": "实际本体扣血会重置这一秒的恢复进度；只有护甲受伤不会重置回血节拍。",
			"其他来源": "睡莲周期治疗使用睡莲自身最大生命作为基数，只治疗当时真正承托的植物；僵尸再生使用各等阶的独立参数。",
			"叠加边界": "不同来源分别施效并受生命上限限制；来源失效、被封锁或死亡后的行为依该来源机制停止。",
		}}],
		"sources": "坚果「不屈」、睡莲治疗转职、高阶舞王等再生能力。",
		"preview": {"subject": "plant", "interval": 1, "fraction": 0.05, "caption": "示例每秒回复5%本体最大生命；满血后不再增加。"},
	},
	# 实现依据：scripts/character/plant/coffee_bean_use_plan.gd；scripts/character/components/component_create_sun.gd；scripts/adventure/research/research_coffee_promotion_books.gd。
	{
		"buff_id": &"sun_yield", "title": "光能亲和",
		"category": "生产增益", "color": Color(0.94, 0.78, 0.28), "symbol": "阳",
		"summary": "咖啡豆为阳光生产者登记永久产值加成，使其之后生产的阳光价值提高50%，不改变生产频率。",
		"stats": {"阳光价值": "＋50%", "同类叠加": "只保留较大加成", "持续时间": "随当前植株保留"},
		"effects": [{"title": "规则与边界", "options": {
			"产值组成": "在当前成长阶段产值及已有生产成长加值的基础上计算，再按原生产入口取整与生成；不反写原始成长阶段数值。",
			"对象与边界": "必须是实际具有阳光生产组件的合适植物。此效果不把攻击伤害转成阳光，和敌人身上的阳光灌注是不同机制。",
		}}],
		"sources": "咖啡豆二转「光能亲和」。",
		"preview": {"subject": "plant", "amount": 0.5, "input": 100, "output": 150, "caption": "示例原本总价值100的产光提高到150，生产间隔不变。"},
	},
	# 实现依据：scripts/adventure/research/adventure_ice_shroom_world.gd；scripts/adventure/research/adventure_ice_shroom_cast.gd；scripts/manager/zombie_manager/zm_zombie_wave_manager.gd。
	{
		"buff_id": &"world_pause", "title": "世界",
		"category": "战场状态", "color": Color(0.49, 0.61, 0.84), "symbol": "止",
		"summary": "寒冰菇施放后，在与本次冻结相同的时限内挂起自然波次推进。这个来源由战场持有，母株离场后仍可继续。",
		"stats": {"持续时间": "本次寒冰菇的冻结时长", "暂停对象": "自然波次推进"},
		"effects": [{"title": "规则与边界", "options": {
			"多来源": "每次施放登记独立的暂停来源，到期只归还自己的来源；其他仍有效的暂停保持不变。",
			"作用边界": "它本身不冻结场上敌人的动作，不能把自然刷怪暂停等同于整场时间停止。角色身上的冰冻由另一个状态单独处理。",
			"生命周期": "菜单暂停不消耗剩余战斗秒；原战局结束、切轮、换阶段或离场时释放该暂停来源。",
		}}],
		"sources": "寒冰菇三转「世界」。",
		"preview": {"subject": "zombie", "rate": 1, "caption": "自然刷怪进度暂停；已在场敌人仍按自己的状态行动。"},
	},
]
