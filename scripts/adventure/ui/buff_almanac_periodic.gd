## Buff 图鉴的持续伤害、削弱及累积标记说明；仅含只读展示数据，不加载战斗场景或施加效果。
extends RefCounted

## 本组条目按固定顺序编排；数值和叠加规则对应每条上方所列的实战实现。
const ENTRIES: Array[Dictionary] = [
	# 实现依据：scripts/adventure/adventure_periodic_damage_effect.gd；scripts/adventure/adventure_poison_effect.gd。
	{
		"buff_id": &"poison", "title": "中毒",
		"category": "持续伤害", "color": Color(0.42, 0.73, 0.35), "symbol": "毒",
		"summary": "每半秒按目标本体最大生命的2%结算一次基础普通伤害；防具生命不进入伤害基数。",
		"stats": {"间隔": "0.5战斗秒", "每跳基础伤害": "本体最大生命×2%，取整", "持续时间": "由来源决定"},
		"effects": [{"title": "规则与边界", "options": {
			"重复与共存": "同种中毒只保留较长剩余时间，不叠加跳伤、不重置下一跳；可与灼烧、缠怨同时存在。",
			"实际结算": "伤害仍经过格挡、减伤、防具和护卫转移；无敌不会掉血。死亡、魅惑、离场或原战局结束时清除。",
		}}],
		"sources": "小喷菇毒性孢子、大喷菇变异喷涌等。",
		"preview": {"subject": "zombie", "interval": 0.5, "fraction": 0.02, "caption": "每0.5秒跳伤一次；示例未加入格挡、减伤或护甲。"},
	},
	# 实现依据：scripts/adventure/adventure_burn_effect.gd；scripts/adventure/adventure_periodic_damage_effect.gd；scripts/adventure/research/adventure_jalapeno_blast.gd。
	{
		"buff_id": &"burn", "title": "灼烧",
		"category": "持续伤害", "color": Color(0.93, 0.43, 0.22), "symbol": "燃",
		"summary": "每半秒造成相当于目标本体最大生命2%的基础普通伤害，并循环显示原生火豆命中火焰。",
		"stats": {"间隔": "0.5战斗秒", "每跳基础伤害": "本体最大生命×2%，取整", "时长／来源倍率": "由施加来源决定"},
		"effects": [{"title": "规则与边界", "options": {
			"重复与共存": "同种灼烧只续到较长剩余时间，不叠伤、不推迟下一跳；中毒和缠怨使用独立节拍。",
			"与寒冷关系": "灼烧状态本身不调用火豆的解冻逻辑，可以和寒冷共存；来源的命中攻击若另有解冰则单独处理。",
			"伤害与结束": "走普通防护结算，部分来源另有末乘倍率；本次灼烧跳伤致死才记为烧死。死亡、魅惑、离场或战局结束时清除。",
		}}],
		"sources": "双发射手余烬、大喷菇灼烧变种、火爆辣椒的持续燃烧。",
		"preview": {"subject": "zombie", "interval": 0.5, "fraction": 0.02, "caption": "独立半秒火焰跳伤；灼烧本身不会解除冰冻。"},
	},
	# 实现依据：scripts/adventure/adventure_resentment_effect.gd；scripts/adventure/adventure_periodic_damage_effect.gd。
	{
		"buff_id": &"resentment", "title": "缠怨",
		"category": "持续伤害", "color": Color(0.55, 0.51, 0.65), "symbol": "怨",
		"summary": "永久附着的持续伤害标记，每一战斗秒结算本体最大生命2%的基础普通伤害，身体呈黑白交替。",
		"stats": {"间隔": "1战斗秒", "基础跳伤": "本体最大生命×2%，取整", "自然到期": "不会"},
		"effects": [{"title": "规则与边界", "options": {
			"重复施加": "不增加伤害、不增加第二条节拍，也不重置下一跳；只更新最新来源归属。",
			"防护与结束": "正常经过格挡、减伤、防具和转伤。死亡、魅惑、真正离场或原战局结束时清除，不跨战斗保留。",
		}}],
		"sources": "双发射手「哈迪斯」区域命中效果。",
		"preview": {"subject": "zombie", "interval": 1, "fraction": 0.02, "caption": "每秒跳伤，黑白闪动；演示重置不代表实战会到期。"},
	},
	# 实现依据：scripts/character/components/hp_component/component_hp.gd；scripts/adventure/adventure_plant_negative_effects.gd。
	{
		"buff_id": &"degradation", "title": "劣化",
		"category": "数值削弱", "color": Color(0.58, 0.55, 0.49), "symbol": "衰",
		"summary": "同时增加承受伤害并降低造成伤害。累计劣化为50%时，基础承伤变为150%，输出变为50%。",
		"stats": {"承伤倍率": "1＋劣化总比例", "输出倍率": "max(0，1−劣化总比例)", "时限": "持续于该目标"},
		"effects": [{"title": "规则与边界", "options": {
			"叠加规则": "普通通道取最强值；明确可叠加的通道按百分点相加；具名效果族只在自己的上限内累计。各通道最终相加。",
			"边界与净化": "总劣化达到100%后输出为零，不会出现负伤害；与脆弱共同增加承伤。植物净化可以清除全部劣化通道。",
		}}],
		"sources": "高阶僵尸啃咬、黑将军／救主攻击、唐吉诃德角色技能、小喷菇／大喷菇／双发射手变种。",
		"preview": {"subject": "zombie", "amount": 0.5, "input": 100, "output": 150, "caption": "示例50%劣化：受到100基础伤害变为150，输出减半。"},
	},
	# 实现依据：scripts/character/components/hp_component/component_hp.gd；scripts/adventure/adventure_plant_negative_effects.gd；scripts/adventure/research/research_snow_pea_promotion_books.gd。
	{
		"buff_id": &"brittleness", "title": "脆弱",
		"category": "数值削弱", "color": Color(0.53, 0.74, 0.89), "symbol": "脆",
		"summary": "每层增加1个百分点的承伤，只影响实际承受者，不降低其攻击输出。",
		"stats": {"每层承伤": "＋1%", "上限": "100层", "100层效果": "基础承伤×2"},
		"effects": [{"title": "规则与边界", "options": {
			"叠加与结算": "不同来源累加到同一目标上，最多100层；与劣化的承伤比例加算，再进入格挡、减伤和护甲结算。",
			"适用与持续": "统一入口只给普通僵尸增加脆弱层数；没有自然衰减计时，随该角色存在。",
		}}],
		"sources": "寒冰射手脆弱转职；寒冰菇「冻原」一次施加50层。",
		"preview": {"subject": "zombie", "amount": 50, "input": 100, "output": 150, "caption": "示例50层脆弱：100基础伤害放大到150，输出不变。"},
	},
	# 实现依据：scripts/adventure/adventure_sun_bean_effect.gd。
	{
		"buff_id": &"sun_infusion", "title": "阳光灌注",
		"category": "特殊标记", "color": Color(0.93, 0.8, 0.23), "symbol": "光",
		"summary": "给敌人附加受伤产光标记。每层把每25点实际战斗血池损失转换为5阳光，未满单位的余数保留。",
		"stats": {"单层兑换": "25实伤→5阳光", "重复施加": "增加1层转换效率", "自发产光": "没有"},
		"effects": [{"title": "规则与边界", "options": {
			"计量范围": "计入本体、装备防具和临时护甲的实际损失；过量伤害、强制卸甲和其他脚本生命调整不计入。",
			"叠加与结束": "多层按实伤加权累计，不创建重复监听；可结算真实末击。死亡、魅惑、离场或原战局结束后清除层数与余数。",
		}}],
		"sources": "大喷菇的阳光豆式变异效果。",
		"preview": {"subject": "zombie", "amount": 1, "input": 25, "output": 5, "caption": "单层示例：实际损失25点生命池，掉落5阳光。"},
	},
	# 实现依据：scripts/adventure/adventure_detonation_charge_effect.gd；scripts/adventure/research/repeater_area_effects.gd。
	{
		"buff_id": &"detonation_charge", "title": "引爆值",
		"category": "特殊标记", "color": Color(0.89, 0.46, 0.35), "symbol": "爆",
		"summary": "把命中点数累积到目标身上；满十点时清零，并由触发满点的来源安排一次爆炸。",
		"stats": {"触发阈值": "10点", "当前双发爆炸": "一格范围，1800基础伤害"},
		"effects": [{"title": "规则与边界", "options": {
			"点数规则": "各来源共用目标的一个计数器；点数不随时间减少，超过十点的余量不保留。死亡、魅惑、离场或战局结束时清空。",
			"爆炸归属": "伤害、倍率和空间判定由最后触发的来源决定，1800是当前双发引爆的基础值，不是通用固定最终伤害。设施不接受此标记。",
		}}],
		"sources": "双发射手引爆变种。",
		"preview": {"subject": "zombie", "amount": 10, "caption": "引爆值累积到10后爆炸并清零，超出点数不保留。"},
	},
]
