## 单个主动技能的静态定义；与时装、商店、HUD 和战斗生命周期解耦。
extends Resource
class_name CharacterSkillDefinition

## 跨版本稳定 ID，必须与 CharacterSkillCatalog 注册键相同。
@export var id: StringName
## 玩家看到的技能名称。
@export var display_name: String
## 技能说明；不在这里拼接 UI 冷却文本。
@export_multiline var description: String
## 战斗按钮的完整图标，运行时按需加载。
@export var icon: Texture2D
## Cut-in 使用的人物全身立绘；通常引用时装原立绘，未设置时使用技能图标。
@export var cut_in_portrait: Texture2D
## 技能名的专用透明字图；未设置时使用 [member display_name] 的文字排版。
@export var cut_in_title: Texture2D
## 成功施放时由共用演出播放的起手音，可为空；命中和落点音效仍由各自效果负责。
@export var cut_in_sound: AudioStream
## Cut-in 斜幕、描边和速度线的主题色。
@export var cut_in_accent: Color = Color("c4a772")
## 让退场沿斜刀口裂开，立绘与标题分别从两侧甩出。
@export var cut_in_blade_exit: bool = false
## 成功释放后进入冷却的游戏秒数；不跟随阶段重置。
@export_range(0.0, 3600.0, 0.1) var cooldown_seconds: float = 120.0
## 为 true 时，首次开战立即进入一轮完整冷却；连续阶段保留剩余时间。
@export var starts_on_cooldown: bool = false
## 通过子资源实现的具体效果；不得把角色 ID 判断写入运行时。
@export var effect: CharacterSkillEffect

## 拒绝无 ID、无有效效果和非法冷却的资源，阻止半成品技能出现在战场。
func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() and icon != null \
		and effect != null and is_finite(cooldown_seconds) \
		and cooldown_seconds >= 0.0 and cooldown_seconds <= 3600.0
