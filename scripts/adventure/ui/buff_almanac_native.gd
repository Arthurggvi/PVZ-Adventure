## Buff 图鉴的原生行为与位移状态说明；仅含只读展示数据，不加载战斗场景或施加效果。
extends RefCounted

## 本组条目按固定顺序编排；数值和叠加规则对应每条上方所列的实战实现。
const ENTRIES: Array[Dictionary] = [
	# 实现依据：scripts/character/components/component_sleep.gd；scripts/character/plant/plant_000_base.gd。
	{
		"buff_id": &"sleep", "title": "日间睡眠",
		"category": "环境状态", "color": Color(0.42, 0.45, 0.72), "symbol": "眠",
		"summary": "需要日眠的蘑菇在日间环境进入睡眠，暂停其睡眠关联的攻击或生产组件。",
		"stats": {"触发条件": "日间＋需要日眠", "结束条件": "夜晚或有效唤醒"},
		"effects": [{"title": "规则与边界", "options": {
			"环境判断": "按关卡的日夜配置判断，黄昏背景本身不决定是否睡眠。无日眠需求的植物不会受此限制。",
			"唤醒来源": "咖啡豆提供永久唤醒，临时光环按来源提供豁免；离开光环后会重新判断环境，永久唤醒仍保留。",
		}}],
		"sources": "蘑菇的原生日眠机制。",
		"preview": {"subject": "plant", "rate": 0, "caption": "睡眠气泡出现，关联攻击与生产暂停。"},
	},
	# 实现依据：scripts/character/components/component_scaredy.gd；scripts/character/plant/plant_014_scaredy_shroom.gd。
	{
		"buff_id": &"scaredy", "title": "近身怯战",
		"category": "行动控制", "color": Color(0.67, 0.51, 0.77), "symbol": "怯",
		"summary": "胆小菇检测到近身敌人时缩起身体，禁用与原生恐惧关联的攻击组件。",
		"stats": {"触发条件": "近身检测到敌人", "持续时间": "敌人仍在检测范围内"},
		"effects": [{"title": "规则与边界", "options": {
			"解除方式": "敌人离开或获得有效的免怯战来源后恢复；不会解除睡眠、死亡或无效化等其他限制。",
			"与恐惧区别": "这是植物的近身反应，不会使僵尸反向逃跑，也不会改变任何阵营。",
		}}],
		"sources": "胆小菇的原生近身反应。",
		"preview": {"subject": "plant", "rate": 0, "caption": "近身敌人令胆小菇缩起并停攻；没有逃跑位移。"},
	},
	# 实现依据：scripts/character/components/component_move.gd；scripts/adventure/research/adventure_cherry_blast.gd；scripts/character/zombie/zombie_000_base.gd。
	{
		"buff_id": &"airborne", "title": "抛起",
		"category": "位移控制", "color": Color(0.73, 0.56, 0.36), "symbol": "浮",
		"summary": "沿强制轨迹把普通僵尸抛离地面。空中暂停自身行动、攻击和普通行走，落地后解除本次控制。",
		"stats": {"高度／距离／时长": "由施加来源决定", "空中动作倍率": "×0"},
		"effects": [{"title": "规则与边界", "options": {
			"重叠轨迹": "连续抛起保留尚未完成的位移和落地回调；水平推移、换行可以与抛起共同合成。",
			"资格边界": "载具与已经被缠绕水草抓住的目标不接受通用强制位移；死亡会取消剩余轨迹。",
		}}],
		"sources": "樱桃炸弹等带抛起轨迹的转职冲击。",
		"preview": {"subject": "zombie", "rate": 0, "caption": "目标抛起、空中停攻，落地后恢复自身行动。"},
	},
	# 实现依据：scripts/character/components/component_move.gd；scripts/adventure/adventure_zombie_wind_gust.gd；scripts/adventure/research/adventure_pea_projectile_effects.gd。
	{
		"buff_id": &"knockback", "title": "击退与风推",
		"category": "位移控制", "color": Color(0.57, 0.69, 0.77), "symbol": "退",
		"summary": "沿水平方向强制移动目标。纯水平推移占用普通行走，不等同于抛起或零速眩晕。",
		"stats": {"位移距离／时长": "由来源决定", "纯水平位移": "不单独停用攻击"},
		"effects": [{"title": "规则与边界", "options": {
			"叠加与终止": "缓动风推的同向重复作用合并到当前终点，不能连续叠成多格；死亡或来源战局失效时取消相应余程。",
			"资格边界": "通用强制位移不作用于载具或已被水草抓住的僵尸；弹体命中还要满足自己的目标规则。",
		}}],
		"sources": "豌豆射手击退火豆／冲击、僵尸风推、明灯波浪对僵尸的水平推移等。",
		"preview": {"subject": "zombie", "rate": 1, "caption": "身体被水平推走；纯击退本身没有眩晕停攻效果。"},
	},
	# 实现依据：scripts/character/zombie/zombie_000_base.gd；scripts/character/components/component_move.gd。
	{
		"buff_id": &"garlic", "title": "大蒜换行",
		"category": "位移控制", "color": Color(0.74, 0.72, 0.58), "symbol": "蒜",
		"summary": "啃食大蒜后，僵尸短暂停顿并尝试转入同类相邻行；换行沿用战场真实地块关系。",
		"stats": {"反应停顿": "0.5秒", "后续行为": "尝试换到相邻行"},
		"effects": [{"title": "规则与边界", "options": {
			"触发与限制": "由啃食大蒜触发，并遵循目标的换行和强制位移资格；没有合法相邻行时不能凭空换行。",
			"状态保留": "同一僵尸换行的短暂重挂不视为真正离场，中毒、灼烧及已登记的多种状态继续计时。",
		}}],
		"sources": "大蒜。",
		"preview": {"subject": "zombie", "rate": 0, "caption": "先短暂停顿，再换到相邻行；不是永久定身。"},
	},
	# 实现依据：scripts/character/components/component_grap.gd；scripts/character/zombie/zombie_000_base.gd。
	{
		"buff_id": &"entangled", "title": "水草缠绕",
		"category": "行动控制", "color": Color(0.32, 0.67, 0.55), "symbol": "缠",
		"summary": "缠绕水草抓住合法目标后，锁定其攻击、行走与游泳姿态，随后把它拖入水下完成处决。",
		"stats": {"抓住等待": "0.5秒", "下沉过程": "0.5秒", "结局": "拖拽完成后死亡"},
		"effects": [{"title": "规则与边界", "options": {
			"受击状态": "抓取后关闭普通受击框并取消尚未完成的强制位移；这是拖拽处决流程，不是到期后恢复的普通眩晕。",
			"生命周期": "藤蔓随目标存在，拖拽随战斗暂停；本状态不提供额外的持续伤害层数。",
		}}],
		"sources": "缠绕水草。",
		"preview": {"subject": "zombie", "rate": 0, "caption": "被抓住后短暂停住并下沉；实战结束时是处决。"},
	},
]
