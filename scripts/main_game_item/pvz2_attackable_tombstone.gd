## 黑暗时代可攻击墓碑，保留占格与生命协议，复用原版墓碑演出的动画和音效。
extends TombStone
class_name PvZ2AttackableTombstone

## 黑暗时代普通墓碑的满血值。
const MAX_HEALTH := 700
## 各裂纹阶段从满血起累计损失的血量。
const DAMAGE_THRESHOLDS := [1, 150, 300, 450]
## 完整碑身和四个裂纹阶段的原版贴图。
const DAMAGE_ART: Array[Texture2D] = [
	preload("res://assets/adventure/structures/pvz2_tombstone_dark/intact.png"),
	preload("res://assets/adventure/structures/pvz2_tombstone_dark/damage_1.png"),
	preload("res://assets/adventure/structures/pvz2_tombstone_dark/damage_2.png"),
	preload("res://assets/adventure/structures/pvz2_tombstone_dark/damage_3.png"),
	preload("res://assets/adventure/structures/pvz2_tombstone_dark/damage_4.png"),
]
## 从 PvZ2 5.8.1 的 Tombstone_Dark_Effects PAM 转成的 Godot 动画，保留原版 30 帧节拍。
const EFFECTS: PackedScene = preload("res://scenes/fx/pvz2_tombstone_effects.tscn")
## 进入每个裂纹阶段时的掉屑动画，最重的阶段掉落较大的碎片。
const DAMAGE_EFFECTS: Array[StringName] = [&"", &"chip_1", &"chip_1", &"chip_2", &"chip_3"]
## 原版关卡配置中的出土音效 Play_Zomb_Egypt_TombRaiser_Grave_Rise。
const RISE_SOUND: AudioStream = preload("res://assets/adventure/structures/pvz2_tombstone_dark/rise.wav")
## 原版 BreakEffectSound 对应的两种 Play_Zomb_Egypt_Grave_Crumble 采样。
const CRUMBLE_SOUNDS: Array[AudioStream] = [
	preload("res://assets/adventure/structures/pvz2_tombstone_dark/crumble_1.wav"),
	preload("res://assets/adventure/structures/pvz2_tombstone_dark/crumble_2.wav"),
]
## 格子中碑身的底边锚点，单位为遮罩局部像素。
const STONE_BOTTOM_Y := 106.0

## 负责受击和生命结算的独立实体。
@onready var damage_receiver: PvZ2TombstoneTarget = $DamageReceiver
## 上一次处理的血量，区分真正受击、无效伤害和恢复。
var _last_hp := MAX_HEALTH
## 当前碑身的裂纹阶段，0 表示完整。
var _damage_stage := 0
## 出土演出是否仍待开始；从存档恢复时跳过出土。
var _rise_pending := true
## 出土时只移动贴图偏移，使出土中受击也能对齐碑身底边。
var _rise_tween: Tween
## 最近一次受击的回弹补间；连续命中时重启回弹。
var _hit_tween: Tween
## 同一实例可能同时收到致死伤害和吞墓完成回调，只破碎一次。
var _destroying := false

## 在子节点初始化前给受击实体设置实际所在行。
func _enter_tree() -> void:
	($DamageReceiver as Character000Base).lane = row_col.x

## 初始化碑身，连接战斗扣血和死亡事件。
func _ready() -> void:
	super._ready()
	damage_receiver.health_changed.connect(_on_health_changed)
	damage_receiver.destroyed.connect(tombstone_death)

## 使用黑暗时代碑身与出土光效；等格子挂载完成后再定位光效。
func _init_tombstone() -> void:
	tombstone.texture = DAMAGE_ART[0]
	tombstone.position.y = STONE_BOTTOM_Y - float(tombstone.texture.get_height()) * 0.5
	tombstone.offset.y = float(tombstone.texture.get_height())
	mound.hide()
	_start_rise.call_deferred()

## 紫色光束落地后将碑身从地面推出。
func _start_rise() -> void:
	if not _rise_pending or _destroying or is_queued_for_deletion():
		return
	_rise_pending = false
	_play_effect(&"rise")
	SoundManager.play_sfx_with_pool(RISE_SOUND)
	_rise_tween = create_tween()
	_rise_tween.tween_property(tombstone, ^"offset:y", 0.0, 0.38) \
			.set_delay(0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## [param current_hp] 本次结算后的生命；非致死伤害会回弹，跨入新阶段时额外掉屑。
func _on_health_changed(current_hp: int) -> void:
	if current_hp <= 0 or _destroying:
		return
	# 只有实际失血触发反馈；治疗或被抵消的攻击仍可刷新外观。
	var took_damage: bool = current_hp < _last_hp
	# 高伤害跨过多个阈值时，只播放最终到达的裂纹阶段特效。
	var old_stage: int = _damage_stage
	_last_hp = current_hp
	update_damage_visual(current_hp)
	if not took_damage:
		return
	_play_hit_recoil()
	if _damage_stage > old_stage:
		_play_effect(DAMAGE_EFFECTS[_damage_stage])

## 给碑身短促震动和亮度回落；只改变精灵表现。
func _play_hit_recoil() -> void:
	if _hit_tween != null:
		_hit_tween.kill()
	tombstone.rotation = -0.035
	tombstone.self_modulate = Color(1.35, 1.35, 1.35)
	_hit_tween = create_tween().set_parallel()
	_hit_tween.tween_property(tombstone, ^"rotation", 0.0, 0.14).set_trans(Tween.TRANS_BACK)
	_hit_tween.tween_property(tombstone, ^"self_modulate", Color.WHITE, 0.11)

## [param current_hp] 当前生命；直接更新裂纹和底部锚点，不播放命中特效。
func update_damage_visual(current_hp: int) -> void:
	# 用累计失血定位阶段，血量超出范围时夹到首尾阶段。
	var damage: int = MAX_HEALTH - clampi(current_hp, 0, MAX_HEALTH)
	var state := 0 # 达到的裂纹阶段。
	for threshold: int in DAMAGE_THRESHOLDS: # 依次检查各阶段所需的累计失血。
		if damage >= threshold:
			state += 1
	if state == _damage_stage:
		return
	var art: Texture2D = DAMAGE_ART[state] # 目标裂纹阶段的原版贴图。
	# 通过贴图高度差保持底边锚定，也保留吞墓者使用的遮罩偏移。
	tombstone.position.y += float(tombstone.texture.get_height() - art.get_height()) * 0.5
	tombstone.texture = art
	_damage_stage = state

## [param animation_name] 原版出土、掉屑或碎裂的单次动画；播放完后释放特效。
func _play_effect(animation_name: StringName) -> void:
	# 将特效挂在格子下，与碑身同坐标，碑身释放后碎片仍可落地。
	var effect: Node2D = EFFECTS.instantiate()
	effect.position = position
	effect.z_index = z_index + 1
	add_sibling(effect)
	var playback: AnimationPlayer = effect.get_node("AnimationPlayer") # 只播放本次需要的片段。
	playback.animation_finished.connect(func(_animation: StringName): effect.queue_free())
	playback.play(animation_name)
	playback.advance(0.0)

## 战斗击碎与吞墓共用破碎演出，立即按墓碑协议释放格子。
func tombstone_death() -> void:
	if _destroying:
		return
	_destroying = true
	_play_effect(&"shatter")
	SoundManager.play_sfx_with_pool(CRUMBLE_SOUNDS.pick_random())
	super.tombstone_death()

## 返回存档使用的墓碑种类标识。
func get_tombstone_kind() -> StringName:
	return &"pvz2"

## 返回伤害组件当前剩余生命，供格子存档。
func get_current_hp() -> int:
	return damage_receiver.hp_component.curr_hp

## [param saved_hp] 存档血量；恢复仍存活的裂纹阶段，并跳过出土与受击演出。
func restore_hp(saved_hp: int) -> void:
	var hp: int = clampi(saved_hp, 1, MAX_HEALTH) # 存档记录的在场墓碑至少保留 1 点生命。
	_rise_pending = false
	if _rise_tween != null:
		_rise_tween.kill()
	tombstone.offset.y = 0.0
	damage_receiver.hp_component.curr_hp = hp
	_last_hp = hp
	update_damage_visual(hp)
