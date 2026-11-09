## Single text catalog; no combat behavior lives here.
extends RefCounted
class_name AdventureZombieTierDescriptions

const DESCRIPTIONS: Dictionary = {
    CharacterRegistry.ZombieType.Z001Norm: {},
    CharacterRegistry.ZombieType.Z002Flag: {
        &"veteran": "在场时为全场友方僵尸提供可叠加的10点固定格挡。",
        &"elite": "在场时提供可叠加的10点格挡；每2秒使全场友军啃咬伤害提高50%，持续0.5秒。",
        &"tier4": "在场时提供可叠加的15点格挡；每2秒使全场友军啃咬伤害提高100%，持续1秒。",
        &"tier5": "继承四阶能力；入场时额外使全场友军获得100%加速与无敌，持续1秒。",
    },
    CharacterRegistry.ZombieType.Z003Cone: {
        &"elite": "路障脱落后自身速度提高20%，持续0.5秒。",
        &"tier4": "路障脱落后自身速度提高50%，持续0.8秒。",
        &"tier5": "路障脱落后自身及周围八向一格友军速度提高50%，持续0.8秒。",
    },
    CharacterRegistry.ZombieType.Z004PoleVaulter: {
        &"veteran": "失去撑杆后永久提高10%移动速度。",
        &"elite": "持杆时减少20%所受伤害并提高30%速度；失杆后速度提高10%。",
        &"tier4": "持杆时减少40%所受伤害、提高50%速度，可连续跳跃两次；失杆后速度提高15%。",
        &"tier5": "继承四阶持杆与失杆强化；可连续跳跃三次，每次跨越两格距离。",
    },
    CharacterRegistry.ZombieType.Z005Bucket: {
        &"veteran": "自身获得10%伤害减免。",
        &"elite": "自身及周围八向一格友军获得20%伤害减免。",
        &"tier4": "自身及周围八向一格友军获得35%伤害减免；铁桶脱落时向该范围友军各授予200点额外护甲。",
        &"tier5": "自身伤害减免提升至50%，周围一格友军仍获35%；铁桶存在期间代替附近友军承受来袭伤害，脱桶时授予200点额外护甲。",
    },

    CharacterRegistry.ZombieType.Z006Paper: {
        &"veteran": "报纸脱落时获得1秒无敌。",
        &"elite": "继承二阶脱报纸后1秒无敌；脱报纸后移动速度提高30%，额外啃咬伤害提高80%。",
        &"tier4": "继承二阶脱报纸后1秒无敌；脱报纸后速度提高50%，额外啃咬伤害提高150%，立即获得500点额外护甲。",
        &"tier5": "继承四阶全部脱报纸强化（包含1秒无敌）；持报纸时起即获得300%常态啃咬伤害加成。",
    },
    CharacterRegistry.ZombieType.Z007ScreenDoor: {
        &"veteran": "铁栅门自身获得10%防具减伤，不影响僵尸本体。",
        &"elite": "铁栅门自身防具减伤提高至30%，不影响本体。",
        &"tier4": "铁栅门自身防具减伤提高至50%，不影响本体。",
        &"tier5": "铁栅门自身防具减伤提高至80%，不影响本体。",
    },
    CharacterRegistry.ZombieType.Z008Football: {
        &"veteran": "自身速度提高5%，受到的伤害减少5%。",
        &"elite": "继承二阶；每次有效受击叠加1%速度。每啃食0.2秒额外啃咬伤害与劣化施加强度各增加1%；被啃食植物获得不叠加的铅灰色劣化。失去啃咬目标后重置计数。",
        &"tier4": "继承三阶；受击叠速每次0.5%，每0.2秒啃咬和劣化增幅各提高2%；每秒获得20点额外护甲。",
        &"tier5": "继承四阶；劣化强度每0.2秒提高4%，脱离啃咬目标后保留劣化施加强度计数；每秒获得60点护甲。",
    },
    CharacterRegistry.ZombieType.Z009Jackson: {
        &"veteran": "首次召唤伴舞前获得50%伤害减免。",
        &"elite": "继承二阶；出场获得200点额外护甲，每次召唤动作均召唤伴舞。",
        &"tier4": "继承三阶；出场护甲提高至400点，每秒回复30点本体生命；死亡时在原地额外召唤一只同阶伴舞。",
        &"tier5": "继承四阶；每次召唤改为四只四阶舞王，均为独立舞团，子代不得继承五阶替换能力。",
    },
    CharacterRegistry.ZombieType.Z010Dancer: {
        &"veteran": "出场获得0.5秒无敌。",
        &"elite": "继承二阶；死亡时触发一次1800点伤害的小丑盒爆炸。",
        &"tier4": "继承二阶；死亡爆炸提高至3000点伤害。",
        &"tier5": "与四阶相同：出场无敌0.5秒，死亡时爆炸造成3000点伤害。",
    },

    CharacterRegistry.ZombieType.Z011Duckytube: {},
    CharacterRegistry.ZombieType.Z012Snorkle: {
        &"veteran": "处于潜水状态时移动速度提高30%。",
        &"elite": "潜水时移速提高50%，每连续潜水1秒获得50点额外护甲。",
        &"tier4": "潜水时移速提高50%，每连续潜水1秒获得100点额外护甲。",
        &"tier5": "潜水时移速提高50%，每连续潜水1秒获得200点额外护甲。",
    },
    CharacterRegistry.ZombieType.Z013Zamboni: {
        &"veteran": "移动速度提高20%，每次有效受击使该速度增幅降低1个百分点，最低归零。",
        &"elite": "继承受击降速；移动速度增幅提高至30%，自身获得20%减伤。",
        &"tier4": "继承受击降速；移动速度增幅提高至50%，自身减伤提高至50%。",
        &"tier5": "继承四阶减伤与受击降速；初始移动速度提高100%，死亡时对周围区域造成1800点爆炸伤害。",
    },
    CharacterRegistry.ZombieType.Z014Bobsled: {
        &"veteran": "雪橇车及其分离后的队员移动速度提高10%。",
        &"elite": "继承二阶移速；无冰道报废所需时间增加100%，可碾压植物。",
        &"tier4": "继承三阶；无冰道报废所需时间增加200%，仍可碾压植物。",
        &"tier5": "继承四阶；完全免疫因没有冰道引起的报废。",
    },
    CharacterRegistry.ZombieType.Z015Dolphinrider: {
        &"veteran": "骑乘海豚期间获得20%减伤。",
        &"elite": "骑乘时减伤提高至30%；一次跳跃最多跨越两个植物格。",
        &"tier4": "骑乘时减伤提高至50%、移速提高10%；一次跳跃跨越两格，对被跃过的植物分别造成300点碾压伤害。",
        &"tier5": "继承四阶骑乘强化；一次跳跃跨越三格，跃过植物所受碾压伤害提升至1800点。",
    },
    CharacterRegistry.ZombieType.Z016Jackbox: {
        &"veteran": "连续啃食植物超过2秒触发自爆，爆炸伤害固定8000。",
        &"elite": "接触到植物时即开始自爆；爆炸伤害固定8000。",
        &"tier4": "速度增加10%；接触植物触发8000点爆炸后失去盒子继续进攻，真正死亡时再次爆炸。",
        &"tier5": "继承四阶能力，两次爆炸伤害均翻倍至16000。",
    },
    CharacterRegistry.ZombieType.Z017Balloon: {
        &"veteran": "气球需命中2次才能击破；飞行时速度提高20%。",
        &"elite": "继承二阶；气球被击破后落地立即自爆并死亡，造成1800点伤害。",
        &"tier4": "气球可承受3次命中；落地自爆伤害提高至3000。",
        &"tier5": "气球可承受5次命中；落地自爆伤害提高至5000。",
    },
    CharacterRegistry.ZombieType.Z018Digger: {
        &"veteran": "地下挖掘时移动速度提高100%。",
        &"elite": "继承二阶；出土后立即恢复向右行走，不再停顿。",
        &"tier4": "继承三阶；地面行走速度提高50%。",
        &"tier5": "继承四阶；死亡时对周围一格内的敌方植物造成1800点爆炸伤害。",
    },
    CharacterRegistry.ZombieType.Z1001BobsledSingle: {
        &"veteran": "从二阶以上雪橇车脱离后继续继承10%移动速度提升。",
        &"elite": "继承二阶雪橇队员移速提升。",
        &"tier4": "继承二阶雪橇队员移速提升。",
        &"tier5": "继承二阶雪橇队员移速提升。",
    },
}


static func get_description(zombie_type: int, tier_id: StringName) -> String:
    var species: Dictionary = DESCRIPTIONS.get(zombie_type, {})
    return str(species.get(tier_id, ""))
