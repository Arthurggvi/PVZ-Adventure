## Buff 图鉴的战斗增益与行为豁免说明；仅含只读展示数据，不加载战斗场景或施加效果。
extends RefCounted

## 本组条目按固定顺序编排；数值和叠加规则对应每条上方所列的实战实现。
const ENTRIES: Array[Dictionary] = [
	# 实现依据：scripts/adventure/adventure_zombie_timed_speed_boost.gd；scripts/character/character_000_base.gd。
	{
		"buff_id": &"speed_boost", "title": "临时加速",
		"category": "战斗增益", "color": Color(0.58, 0.77, 0.38), "symbol": "疾",
		"summary": "在独立的等阶加速通道提高角色速度，作用于读取角色整体速度的移动、动作和计时。",
		"stats": {"倍率／时长": "由来源决定", "同通道输出": "取有效来源的最高倍率"},
		"effects": [{"title": "规则与边界", "options": {
			"重叠规则": "同倍率、同归属的记录取较长剩余时间；不同倍率独立到期，同通道不指数叠加。仍与其他独立速度通道组合。",
			"沉默与结束": "自身等阶来源被沉默时遮蔽并暂停计时；外部授予的加速独立保留。死亡、魅惑或真正离场时清除。",
		}}],
		"sources": "旗帜／扶梯等僵尸增益、白爵士狂暴、救主横扫等。",
		"preview": {"subject": "zombie", "rate": 2, "caption": "示例2倍加速；实际倍率与期限取决于来源。"},
	},
	# 实现依据：scripts/adventure/adventure_zombie_timed_combat_buff.gd；scripts/adventure/adventure_zombie_flag_command.gd。
	{
		"buff_id": &"bite_boost", "title": "啃咬强化",
		"category": "战斗增益", "color": Color(0.83, 0.55, 0.34), "symbol": "噬",
		"summary": "临时提高僵尸普通啃咬的伤害倍率，不直接增加生命、护甲或移动速度。",
		"stats": {"倍率／时长": "由来源决定", "同通道输出": "取有效记录最高值"},
		"effects": [{"title": "规则与边界", "options": {
			"重复规则": "同倍率、同归属的记录延至较长剩余时间；不同倍率分别到期，不把同通道倍率连续相乘。",
			"状态联动": "自身等阶来源被沉默时暂停并遮蔽，外部增益按自身期限保留。死亡、魅惑或真正离场会清除啃咬增益。",
		}}],
		"sources": "高阶旗帜僵尸的啃咬鼓舞等。",
		"preview": {"subject": "zombie", "amount": 2, "input": 100, "output": 200, "caption": "示例2倍啃咬：100基础啃咬提高到200，动作速度不变。"},
	},
	# 实现依据：scripts/character/plant/plant_000_base.gd；scripts/character/components/coffee_plant_boost.gd；scripts/adventure/research/adventure_pea_synergy_runtime.gd；scripts/adventure/research/adventure_sunflower_promotion_runtime.gd。
	{
		"buff_id": &"attack_boost", "title": "植物增伤",
		"category": "战斗增益", "color": Color(0.89, 0.54, 0.36), "symbol": "攻",
		"summary": "为植物登记独立增伤来源。各来源加成先相加，再与卡片本身的伤害倍率组合。",
		"stats": {"独立来源合成": "1＋各来源加成之和", "咖啡绿原酸示例": "＋50%，10秒"},
		"effects": [{"title": "规则与边界", "options": {
			"来源差异": "圣战提供100%增伤；豌豆协同按符合条件的邻接关系各加10%。光环撤销只移除自己的加成。",
			"咖啡规则": "绿原酸对清醒目标消耗10%最大生命，成功后授予10秒增伤；同族重新设置期限和加成，不累加第二份来源。",
			"输出边界": "最终输出仍会受劣化等修正；具体攻击是否使用增伤沿用该植物的真实伤害路径。",
		}}],
		"sources": "向日葵「圣战」、豌豆射手「协同」、咖啡豆「绿原酸」。",
		"preview": {"subject": "plant", "amount": 0.5, "input": 100, "output": 150, "caption": "示例50%增伤：100基础输出变为150，攻击间隔不变。"},
	},
	# 实现依据：scripts/character/components/attack_behavior_component/component_attack_bullet_base.gd；scripts/character/components/component_magnet.gd；scripts/character/components/coffee_plant_boost.gd；scripts/adventure/research/adventure_scaredy_trait_output.gd。
	{
		"buff_id": &"attack_rate", "title": "植物攻速提升",
		"category": "战斗增益", "color": Color(0.8, 0.69, 0.35), "symbol": "速",
		"summary": "只加快支持此效果的植物攻击时钟与攻击动画，不加快产光、成长或整株的其他行为。",
		"stats": {"独立攻击来源": "加成相加", "咖啡因示例": "＋50%，10秒"},
		"effects": [{"title": "规则与边界", "options": {
			"来源合成": "各攻击来源按相对基础攻速相加，仍与原有角色速度组合；同类共生词条先取较强值，避免重复传播叠加。",
			"咖啡规则": "咖啡因对清醒目标消耗10%最大生命后授予加速；同族重置期限，不堆叠第二份咖啡因。",
			"固定周期例外": "明确以固定战斗秒运行的持续喷涌保留自己的伤害周期；不能把所有持续技能一概按普通攻速加快。",
		}}],
		"sources": "咖啡豆「咖啡因」、胆小菇攻速／群落及共生共享。",
		"preview": {"subject": "plant", "rate": 1.5, "caption": "示例50%攻速提升；产光和成长速度保持原规则。"},
	},
	# 实现依据：scripts/adventure/research/adventure_ice_shroom_dynasty.gd；scripts/adventure/research/adventure_ice_shroom_cast.gd；scripts/character/character_000_base.gd。
	{
		"buff_id": &"dynasty", "title": "皇朝",
		"category": "战斗增益", "color": Color(0.8, 0.68, 0.4), "symbol": "朝",
		"summary": "寒冰菇施放时，为当时存活的友方植物恢复50%最大生命，并授予2倍攻速。",
		"stats": {"即时治疗": "最大生命的50%，不超过上限", "攻速倍率": "×2", "持续时间": "本次寒冰菇的冻结时长"},
		"effects": [{"title": "规则与边界", "options": {
			"重复施放": "每次施放分别计时，但所有皇朝共用一个2倍因子，不叠成4倍、8倍；最后一个来源结束才撤销。",
			"生产豁免": "生产与成长的速度计算专门排除皇朝因子；不会因此让阳光生产或成长翻倍。",
			"作用名单": "仅施放时当前有效的友方植物获得该次效果；死亡、离场、转敌或战局结束时清除。",
		}}],
		"sources": "寒冰菇四转「皇朝」。",
		"preview": {"subject": "plant", "rate": 2, "fraction": 0.5, "caption": "施放时回血并授予2倍攻速；重叠皇朝不再翻倍。"},
	},
	# 实现依据：scripts/character/components/component_sleep.gd；scripts/adventure/research/adventure_mushroom_awake_aura.gd；scripts/adventure/research/research_plant_event_dispatch.gd。
	{
		"buff_id": &"awake", "title": "唤醒与常醒",
		"category": "战斗增益", "color": Color(0.87, 0.77, 0.42), "symbol": "醒",
		"summary": "让需要日眠的蘑菇在日间继续活动。永久唤醒、临时光环和出生常醒各自保留原因。",
		"stats": {"咖啡豆": "完成唤醒后永久生效", "临时光环": "至少一个有效来源即可"},
		"effects": [{"title": "规则与边界", "options": {
			"来源独立": "临时唤醒按来源登记，不重复计数；最后一个临时来源离开后重新判断日夜，咖啡豆的永久唤醒不会被撤销。",
			"边界": "唤醒只解除睡眠原因，不解除无效化、死亡或近身怯战；已经清醒时重复刷新不会重启原有攻击或生产计时。",
		}}],
		"sources": "咖啡豆；蘑菇耐日转职、阳光菇「月光蔓延」、胆小菇共生。",
		"preview": {"subject": "plant", "rate": 1, "caption": "睡眠气泡消失并恢复活动；其他行动限制仍独立存在。"},
	},
	# 实现依据：scripts/character/components/component_scaredy.gd；scripts/adventure/research/adventure_scaredy_trait_output.gd。
	{
		"buff_id": &"fearless", "title": "免怯战",
		"category": "战斗增益", "color": Color(0.74, 0.73, 0.46), "symbol": "勇",
		"summary": "使具有近身怯战组件的植物在敌人贴近时仍可攻击；近身检测继续记录敌人位置。",
		"stats": {"作用范围": "植物原生近身怯战", "来源条件": "至少一个有效免怯战来源"},
		"effects": [{"title": "规则与边界", "options": {
			"多来源": "每个来源独立登记；撤销最后一个来源后立即按当前近身敌人重新判断，不会清除其他来源。",
			"能力边界": "不是所有负面状态的免疫，也不解除睡眠或无效化；对本来没有近身怯战机制的植物不新增行为。",
		}}],
		"sources": "胆小菇近身伤害转职及共生共享。",
		"preview": {"subject": "plant", "rate": 1, "caption": "敌人贴近时仍能攻击；只覆盖近身怯战。"},
	},
]
