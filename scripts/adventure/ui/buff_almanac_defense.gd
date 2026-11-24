## Buff 图鉴的防护与免疫状态说明；仅含只读展示数据，不加载战斗场景或施加效果。
extends RefCounted

## 本组条目按固定顺序编排；数值和叠加规则对应每条上方所列的实战实现。
const ENTRIES: Array[Dictionary] = [
	# 实现依据：scripts/character/components/damage_block_effect.gd；scripts/character/components/hp_component/component_hp.gd；scripts/character/components/zombie_block_aura.gd。
	{
		"buff_id": &"damage_block", "title": "固定格挡",
		"category": "防护增益", "color": Color(0.3, 0.75, 0.68), "symbol": "挡",
		"summary": "每次伤害先扣除固定格挡值，最低降到零；格挡不是会被一次性消耗的护甲生命池。",
		"stats": {"单次伤害": "max(0，放大后伤害−格挡)", "来源期限": "由自身特性或光环决定"},
		"effects": [{"title": "规则与边界", "options": {
			"叠加规则": "普通格挡来源只取最高值；明确可叠加的旗帜格挡按来源求和，再加到普通最高值上。",
			"结算顺序": "先处理劣化／脆弱的承伤放大，再扣格挡，然后计算百分比减伤。离开光环或来源被撤销后失去相应贡献。",
		}}],
		"sources": "高阶僵尸的自身格挡、旗帜等格挡光环。",
		"preview": {"subject": "zombie", "amount": 30, "input": 100, "output": 70, "caption": "示例30点格挡：100伤害剩70；格挡本身不被消耗。"},
	},
	# 实现依据：scripts/character/components/damage_reduction_effect.gd；scripts/character/components/hp_component/component_hp.gd。
	{
		"buff_id": &"damage_reduction", "title": "百分比减伤",
		"category": "防护增益", "color": Color(0.3, 0.64, 0.81), "symbol": "减",
		"summary": "在固定格挡之后按比例降低伤害，各独立来源通过剩余伤害相乘组合。",
		"stats": {"双50%来源原始合成": "75%", "普通承伤软化规则": "超过70%的部分只计30%"},
		"effects": [{"title": "规则与边界", "options": {
			"普通生命路径": "合成值不高于70%时原样生效；超过70%时为70%＋超出部分×30%。例如两份50%减伤原始合成为75%，最终按71.5%减伤生效。",
			"防具与撤销": "专属防具抗性使用原始乘积，不套普通承伤的软化规则。每个来源独立撤销，不能把两个50%直接相加为无敌。",
		}}],
		"sources": "铁桶护卫光环、僵尸等阶防护、向日葵「圣战」、提拉米苏「花冠守护」等。",
		"preview": {"subject": "zombie", "amount": 0.5, "input": 100, "output": 50, "caption": "单个50%减伤示例：100伤害剩50。多来源需组合计算。"},
	},
	# 实现依据：scripts/character/components/damage_transfer_effect.gd；scripts/character/components/hp_component/component_hp_zombie.gd；scripts/adventure/adventure_zombie_tier_field.gd。
	{
		"buff_id": &"damage_transfer", "title": "护卫转伤",
		"category": "防护增益", "color": Color(0.43, 0.64, 0.77), "symbol": "护",
		"summary": "符合条件的附近护卫代替受保护僵尸承受原始命中，并使用护卫自己的格挡、减伤和防具结算。",
		"stats": {"范围": "横向一格内、相差不超过一行", "护卫要求": "存活且仍有一类防具"},
		"effects": [{"title": "规则与边界", "options": {
			"选择与结算": "有多个合格护卫时选择最近者，同距稳定择一。转移后不再次串联转给另一名护卫，不复制一份伤害。",
			"失效条件": "护卫失甲、死亡、魅惑、离开范围或等阶能力被压制后失去相应保护。真正受伤、损失血池和击杀归属以承伤者为准。",
		}}],
		"sources": "带转伤能力的高阶铁桶僵尸。",
		"preview": {"subject": "zombie", "input": 100, "output": 0, "caption": "被保护者不扣这笔生命，命中交给护卫重新结算。"},
	},
	# 实现依据：scripts/character/components/hp_component/component_hp_plant.gd；scripts/character/components/hp_component/component_hp_zombie.gd；scripts/adventure/research/adventure_wallnut_promotion_effects.gd。
	{
		"buff_id": &"temporary_armor", "title": "临时护甲",
		"category": "防护增益", "color": Color(0.29, 0.74, 0.84), "symbol": "甲",
		"summary": "独立且可消耗的额外防护池，在普通防护结算后优先吸收攻击；不增加本体最大生命。",
		"stats": {"授予数量／上限": "由来源决定", "消耗方式": "逐次吸收实际伤害"},
		"effects": [{"title": "规则与边界", "options": {
			"叠加与生命": "正数护甲可以相加；部分来源限制本次授甲的总量。护甲不进入本体百分比伤害、恢复或生命上限的基数。",
			"结算与旁路": "植物在格挡、减伤、单次上限之后扣护甲；僵尸临时护甲优先于装备和本体吸收。铲除、处决和强制卸甲等按原有旁路处理。",
		}}],
		"sources": "坚果守护／积甲、睡莲护甲、咖啡豆强效阵痛、高阶僵尸授甲。",
		"preview": {"subject": "plant", "amount": 100, "input": 60, "output": 0, "caption": "100护甲吸收60伤害后剩40，本体生命不变。"},
	},
	# 实现依据：scripts/character/components/hp_component/component_hp.gd；scripts/adventure/adventure_zombie_timed_combat_buff.gd；scripts/adventure/research/adventure_jalapeno_nirvana.gd。
	{
		"buff_id": &"immunity", "title": "伤害无敌",
		"category": "防护增益", "color": Color(0.91, 0.8, 0.43), "symbol": "免",
		"summary": "任意有效无敌来源存在时，普通战斗伤害结算为零；生命组件显示对应的无敌滤镜。",
		"stats": {"普通战斗伤害": "0", "持续时间": "由来源或阶段决定"},
		"effects": [{"title": "规则与边界", "options": {
			"来源组合": "多个来源各自保持，至少一个有效即可无敌。同类限时记录保留较长剩余时间。",
			"与负面状态": "伤害无敌不等于负面免疫；不保证挡住控制、劣化或标记。脚本处决及其他明确的非战斗旁路仍按原规则执行。",
			"沉默与魅惑": "自身等阶无敌被沉默时遮蔽并暂停计时；魅惑后是否保留由该来源明确决定。",
		}}],
		"sources": "旗帜鼓舞、报纸暴怒、部分首领技能、火爆辣椒「涅槃」等。",
		"preview": {"subject": "zombie", "input": 100, "output": 0, "caption": "普通100伤害被无敌挡下；控制效果另行判断。"},
	},
	# 实现依据：scripts/adventure/adventure_plant_negative_effects.gd；scripts/adventure/research/research_plant_event_dispatch.gd；scripts/character/enemy_structure_base.gd。
	{
		"buff_id": &"negative_immunity", "title": "负面状态免疫",
		"category": "防护增益", "color": Color(0.72, 0.83, 0.65), "symbol": "净",
		"summary": "拒绝经统一负面状态入口施加的效果，例如劣化、无效化、中毒、寒冷或眩晕。",
		"stats": {"普通伤害": "仍按防护正常结算", "免疫范围": "由角色／转职规则决定"},
		"effects": [{"title": "规则与边界", "options": {
			"植物规则": "坚果「摧锋」在出生时获得登记负面免疫，入口在派发具体状态前拒绝施加。其他实体也可有自身的负面资格规则。",
			"能力边界": "这不是伤害无敌，也不是日间常醒；不会因此免疫普通攻击、铲除或所有原生环境行为。",
			"专用控制": "明灯震颤直接施加原生冰控，不由植物「摧锋」的登记负面免疫标记拦截。",
		}}],
		"sources": "坚果「摧锋」；敌方设施等实体的固有负面免疫规则。",
		"preview": {"subject": "plant", "input": 100, "output": 100, "caption": "负面标记被拒绝，普通攻击仍可扣血。"},
	},
	# 实现依据：scripts/character/components/hp_component/component_hp_plant.gd；scripts/adventure/research/research_existing_promotion_books.gd。
	{
		"buff_id": &"hit_cap", "title": "单次伤害上限",
		"category": "防护增益", "color": Color(0.61, 0.74, 0.52), "symbol": "限",
		"summary": "限制一次战斗命中的有效伤害。坚果四转「不屈」将单次上限设为本体最大生命的2%。",
		"stats": {"坚果上限": "每次最多最大生命的2%", "取整": "向上取整，至少1点"},
		"effects": [{"title": "规则与边界", "options": {
			"结算位置": "先算劣化、格挡和减伤，再应用本次上限，最后消耗临时护甲；主伤与同击附伤共享这一次上限。",
			"边界": "连续多次命中各自受限，不能把整个技能的多段伤害合并成一次。强制处决、铲除等旁路不受此上限保护。",
		}}],
		"sources": "坚果四转「不屈」。",
		"preview": {"subject": "plant", "amount": 0.02, "fraction": 0.02, "input": 100, "output": 2, "caption": "最大生命100的示例：单次100伤害在护甲前限为2。"},
	},
]
