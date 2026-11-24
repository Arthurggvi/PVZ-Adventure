## 可复用的普通、噩梦和 Boss 战斗曲配置，仅随使用它的关卡加载。
## 当前阶段仍来自 AdventureSession，本资源不保存进度或自行播放音乐。
extends Resource
class_name BattleMusicProfile

## 普通战斗默认曲目，空值沿用原版关卡音乐。
@export var normal_music: AudioStream
## 噩梦及终末等待 Boss 入场时的曲目，空值回退普通曲。
@export var nightmare_music: AudioStream
## 存活 Boss 的专属曲目，空值沿用原有 Boss 音乐。
@export var boss_music: AudioStream

## 按 [param phase_kind] 和 [param has_boss] 解析曲目，返回 null 时由调用方沿用旧配置。
## Boss 优先于阶段；Boss 退场后恢复对应阶段曲目。
func resolve(phase_kind: StagePhaseDefinition.Kind, has_boss: bool) -> AudioStream:
	if has_boss:
		return boss_music
	if phase_kind in [StagePhaseDefinition.Kind.NIGHTMARE, StagePhaseDefinition.Kind.TERMINAL] \
		and nightmare_music != null:
		return nightmare_music
	return normal_music
