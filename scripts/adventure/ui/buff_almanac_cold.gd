## Buff 图鉴的寒冷状态说明；仅含只读展示数据，不加载战斗场景或施加效果。
extends RefCounted

## 本组条目按固定顺序编排；数值和叠加规则对应每条上方所列的实战实现。
const ENTRIES: Array[Dictionary] = [
	# 实现依据：scripts/character/character_000_base.gd；scripts/character/zombie/zombie_013_zamboni.gd；scripts/character/zombie_boss/z_b_000_base.gd。
	{
		"buff_id": &"ice_slow", "title": "寒冷减速",
		"category": "寒冷控制", "color": Color(0.32, 0.73, 0.9), "symbol": "缓",
		"summary": "原生寒冷把角色的动作速度降至一半；移动、动画及使用这一速度的攻击计时会一起减慢。",
		"stats": {"速度倍率": "×0.5", "持续时间": "由施加来源决定"},
		"effects": [{"title": "规则与边界", "options": {
			"重复施加": "保留较长的剩余时间，不把同种减速反复相乘。与深寒减速重叠仍为半速。",
			"解除与抵抗": "火豆、火爆辣椒等解冰攻击可解除原生寒冷。冰车、雪橇车和首领等寒冷免疫目标不受此状态。",
		}}],
		"sources": "寒冰射手、寒冰菇冻后减速；大喷菇、小喷菇、双发射手寒冷变种；明灯震颤对僵尸的6秒减速。",
		"preview": {"subject": "zombie", "rate": 0.5, "caption": "对比原速与半速；实际时长取决于来源。"},
	},
	# 实现依据：scripts/character/character_000_base.gd；scripts/character/zombie/zombie_017_balloon.gd；scripts/character/zombie/zombie_019_pogo.gd；scripts/character/zombie/zombie_025_imp.gd。
	{
		"buff_id": &"ice_freeze", "title": "冰冻",
		"category": "寒冷控制", "color": Color(0.29, 0.65, 0.93), "symbol": "冻",
		"summary": "原生冻结将动作速度设为零，到期后接入来源指定的寒冷减速。",
		"stats": {"动作倍率": "×0", "冻结／冻后减速": "分别由来源指定"},
		"effects": [{"title": "规则与边界", "options": {
			"重复与解冻": "重复冻结保留较长的剩余冻结时间；冻后减速参数由最近一次施加更新。火焰解冰可提前结束原生冻结。",
			"物种差异": "气球、持杆跳跳和仍在投掷／落地阶段的小鬼只能减速。冰车、雪橇车和首领保留原生寒冷免疫。",
			"附带伤害": "普通原生冻结通常附带20点基础真实伤害；冰痕等纯控制入口不附伤。真正解冻后有1秒冻结值保护期。",
		}}],
		"sources": "寒冰菇、冻结值满点；明灯震颤对植物施加3秒纯冰冻及4秒后续减速。",
		"preview": {"subject": "zombie", "rate": 0, "caption": "冻结时动作停住；结束后可继续寒冷减速。"},
	},
	# 实现依据：scripts/adventure/adventure_deep_cold.gd；scripts/adventure/research/adventure_ice_shroom_cast.gd；scripts/adventure/skills/character_skill_control_gateway.gd；scripts/adventure/skills/eve_aurora_starfall.gd。
	{
		"buff_id": &"deep_cold", "title": "深寒",
		"category": "寒冷控制", "color": Color(0.28, 0.45, 0.88), "symbol": "寒",
		"summary": "具有独立期限的特殊寒冷。减速与冻结分别计时，火焰解冰不会清除它。",
		"stats": {"减速倍率": "×0.5", "冻结倍率": "×0", "火焰解除": "无效"},
		"effects": [{"title": "规则与边界", "options": {
			"重复施加": "减速与冻结各自保留较长剩余时间；与原生寒冷减速共存仍为半速。两个冻结来源都结束后才真正解冻。",
			"适用与结束": "沿用目标的寒冷资格；抗冻结但可寒冷的目标仍能减速。死亡、魅惑、离场或原战局结束时清除。",
			"来源差异": "寒冰菇「深寒」使冻结和后续减速各延长2秒；寒冰射手的特殊寒冷按对应转职参数施加。",
			"角色技能": "大肥鱼「冻结海洋」施加5秒纯深寒，不附加原生冻伤或暂停刷怪；伊芙「极光星弹」施加5秒特殊减速，不完全冻结。",
		}}],
		"sources": "寒冰菇「深寒」、寒冰射手特殊寒冷、大肥鱼「冻结海洋」、伊芙「极光星弹」。",
		"preview": {"subject": "zombie", "rate": 0, "caption": "火焰经过后特殊寒冷仍保留，普通解冰不会取消深寒。"},
	},
	# 实现依据：scripts/adventure/adventure_freeze_charge_effect.gd；scripts/character/character_000_base.gd。
	{
		"buff_id": &"freeze_charge", "title": "冻结值",
		"category": "寒冷控制", "color": Color(0.25, 0.42, 0.78), "symbol": "积",
		"summary": "各来源把冻结点数累积在同一个目标身上。未满十点时，只降低基础行走速度，不降低啃咬攻速。",
		"stats": {"每点基础移速": "−10%", "触发阈值": "10点", "满点效果": "3秒冰冻＋5秒减速"},
		"effects": [{"title": "规则与边界", "options": {
			"点数规则": "点数不随时间衰减；满十点立即清零，超出的点数不保留。死亡、魅惑、离场或战局结束时清空。",
			"保护与免疫": "已经冻结及真正解冻后1秒内不能获得新点数；寒冷免疫目标不能累积。只能减速的物种满点仍按其资格处理。",
			"伤害差异": "普通满点调用原生冻伤；冰痕的纯控制来源只冻结，不追加原生20点冻伤。",
		}}],
		"sources": "寒冰射手、大喷菇和双发射手的冻结变种；地面冰痕。",
		"preview": {"subject": "zombie", "amount": 5, "rate": 0.5, "caption": "冻结值逐点降低行走速度，满10点触发冻结并清零。"},
	},
]
