extends Node2D
## 角色身体属性，用于管理body变换（发亮、颜色）
class_name BodyCharacter

## 模仿者材质
const IMITATER = preload("res://shader_material/imitater.tres")

## 身体上下遮罩材质模板；使用时复制，避免不同角色共享裁剪高度。
const BODY_MASK = preload("res://shader_material/body_mask.tres")
## 复生僵尸与白爵士共用的背部白炎帧。
const WHITE_FLAME_MANTLE: SpriteFrames = preload("res://assets/adventure/zombies/white_duke/fx/white_flame_mantle.tres")
var hit_tween: Tween = null  # 发光动画
var light_and_dark_tween: Tween = null  # 明暗交替动画

# modulate 状态颜色变量
var base_color := Color(1, 1, 1)

## 抛飞在身体父节点局部坐标系中的偏移。普通姿态通过 [member pose_position] 与其合成。
var _forced_pose_offset: Vector2 = Vector2.ZERO
## 入水、出土等动作使用的局部身体位置，独立于抛飞的高度。
var pose_position: Vector2:
	get:
		return position - _forced_pose_offset
	set(value):
		position = value + _forced_pose_offset


## 将身体沿世界坐标向上抬 [param height] 像素。设为 0 后回到当前姿态，脚点和受击框保持在地面。
func set_forced_lift(height: float) -> void:
	var base: Vector2 = pose_position # 先保存当前姿态，避免覆盖并行的入水或出土过渡。
	var parent_node := get_parent() as Node2D # 角色缩放会影响局部位移，需用其逆变换。
	_forced_pose_offset = parent_node.global_transform.affine_inverse().basis_xform(Vector2.UP * height)
	pose_position = base


## 各表现因素对应的颜色乘数；最终逐项相乘，白色表示该因素不改变颜色。
var change_color:Dictionary[E_ChangeColors, Color] = {
}
enum E_ChangeColors{
	HitColor,	## 受击闪光的颜色乘数。
	IceColor,	## 冰冻和减速使用一个
	BeShovelLookColor,	## 铲子选中或预览角色时的颜色乘数。
	HypnoColor,	## 被魅惑后的身体染色。
	CreateSunColor,	## 生产阳光时的表现颜色。
	LightAndDark,	## 明暗交替颜色变化(紫卡种植\咖啡豆)
	CharredBlack,	## 被炸弹炸黑
	DamageBlock,	## 固定格挡的淡青色滤镜。
	Degradation,	## 铅灰色劣化；独立于冰冻、受击和格挡。
	BossPhaseTwo,	## Boss 二阶段独立闪黑，保留冰冻与受击颜色。
	WhiteFlameRevival,	## 复生僵尸的白光呼吸，与受击等状态分别合成。
	DamageImmunity,	## 伤害免疫期间叠加在身体上的红色滤镜。
	FreezeCharge, ## 冻结值的独立深蓝滤镜，不覆盖原生冰冻与减速颜色。
	Fear, ## 恐惧的独立黑色滤镜，结束时仅清除此因素。
	Silence, ## 沉默的独立灰色明度滤镜，保留其他状态颜色。
	SunInfusion, ## 光能的独立黄色状态标记，不覆盖其他颜色来源。
	DeepCold, ## 深寒的抗火蓝色滤镜，普通解冻不会擦除。
	Resentment, ## 缠怨的独立黑白明度脉冲，不覆盖受击、寒冷或水面材质。
}

## 二阶段循环补间，与普通明暗交替互不占用。
var boss_phase_tween: Tween

## 挂在身体上的小型白炎，随身体移动、翻转并接受出土裁切。
var _revival_mantle: AnimatedSprite2D
## 由白炎节点绑定的呼吸补间，死亡时停止。
var _revival_tween: Tween


## 给已入树的复生僵尸挂载白炎和循环闪白；同一个身体只挂载一次。
func start_white_flame_revival() -> void:
	# 身体的直接父节点负责发出角色死亡信号。
	var character := get_parent() as Character000Base
	if character == null or character.is_death or is_instance_valid(_revival_mantle):
		return
	_revival_mantle = AnimatedSprite2D.new()
	_revival_mantle.name = "RevivalWhiteFlame"
	_revival_mantle.sprite_frames = WHITE_FLAME_MANTLE
	_revival_mantle.position = Vector2(-3, -53)
	_revival_mantle.scale = Vector2(0.42, 0.46)
	_revival_mantle.self_modulate.a = 0.56
	# 白炎薄薄覆在身体上，体型较宽的僵尸也能看见火苗。
	_revival_mantle.z_index = 1
	add_child(_revival_mantle)
	_revival_mantle.play(&"rise")
	_revival_mantle.frame = get_instance_id() % _revival_mantle.sprite_frames.get_frame_count(&"rise")

	# 轻微错开呼吸周期，避免同批复生的僵尸整齐闪白。
	var rest_time := 0.27 + 0.055 * float(get_instance_id() % 11)
	_revival_tween = _revival_mantle.create_tween().set_loops()
	_revival_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_revival_tween.tween_method(_set_revival_brightness, 1.0, 1.85, 0.30)
	_revival_tween.tween_method(_set_revival_brightness, 1.85, 1.0, 0.90)
	_revival_tween.tween_interval(rest_time)
	character.signal_character_death.connect(_stop_white_flame_revival, CONNECT_ONE_SHOT)


## [param brightness] 白光呼吸的颜色乘数；1 表示恢复正常亮度。
func _set_revival_brightness(brightness: float) -> void:
	set_other_color(E_ChangeColors.WhiteFlameRevival, Color(brightness, brightness, brightness))


## 角色死亡时清除白炎和闪白通道，保留其余受击与状态颜色。
func _stop_white_flame_revival() -> void:
	_revival_tween.kill()
	_revival_mantle.hide()
	_revival_mantle.queue_free()
	change_color.erase(E_ChangeColors.WhiteFlameRevival)
	_update_modulate()


## [param enabled] 是否开启二阶段缓慢闪黑；停用时恢复本通道白色。
func set_boss_phase_pulse(enabled: bool) -> void:
	if is_instance_valid(boss_phase_tween):
		boss_phase_tween.kill()
	set_other_color(E_ChangeColors.BossPhaseTwo, Color.WHITE)
	if not enabled:
		return
	boss_phase_tween = create_tween().set_loops()
	boss_phase_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	boss_phase_tween.tween_method(_set_boss_phase_color, 1.0, 0.22, 1.25)
	boss_phase_tween.tween_method(_set_boss_phase_color, 0.22, 1.0, 1.25)

## [param brightness] 身体颜色乘数，透明度保持为 1。
func _set_boss_phase_color(brightness: float) -> void:
	set_other_color(E_ChangeColors.BossPhaseTwo, Color(brightness, brightness, brightness))


func owner_be_hypno():
	set_other_color(E_ChangeColors.HypnoColor, Color(1,0.5,1))


## [param enabled] 是否叠加无敌红色滤镜；解除时仅移除该颜色因素。
func set_damage_immunity_tint(enabled: bool) -> void:
	if enabled:
		set_other_color(E_ChangeColors.DamageImmunity, Color(1.0, 0.35, 0.35))
	elif change_color.erase(E_ChangeColors.DamageImmunity):
		_update_modulate()


## [param change_name] 要设置的颜色因素，用于与其他状态颜色分别保存并合成。
## [param value] 该颜色因素的乘数，白色表示不改变最终颜色。
func set_other_color(change_name:E_ChangeColors, value: Color) -> void:
	change_color[change_name] = value
	_update_modulate()


## 更新最终 modulate 的合成颜色
func _update_modulate():
	# 本次合成的最终身体颜色，从基础颜色开始累乘各状态颜色。
	var final_color = base_color
	# 当前状态因素提供的颜色乘数，参与最终 modulate 合成。
	for change_color_value in change_color.values():
		final_color *= change_color_value
	modulate = final_color


## 发光动画函数
func body_light():
	## 先直接变亮
	set_other_color(E_ChangeColors.HitColor, Color(2, 2, 2))

	if hit_tween and hit_tween.is_running():
		hit_tween.kill()

	hit_tween = create_tween()
	hit_tween.tween_method(
		func(val): set_other_color(E_ChangeColors.HitColor, val), # val 为补间当前颜色，写入对应颜色因素。
		change_color[E_ChangeColors.HitColor],
		Color(1, 1, 1),
		0.5
	)

## 身体明暗交替(紫卡植物种植时显示)
func body_light_and_dark():
	if light_and_dark_tween and light_and_dark_tween.is_running():
		light_and_dark_tween.kill()
	light_and_dark_tween = create_tween()
	light_and_dark_tween.set_loops()
	light_and_dark_tween.tween_method(
		func(val): set_other_color(E_ChangeColors.LightAndDark, val), # val 为补间当前颜色，写入对应颜色因素。
		Color(0.6, 0.6, 0.6),
		Color(2.0, 2.0, 2.0, 1.0),
		0.5
	)
	light_and_dark_tween.tween_method(
		func(val): set_other_color(E_ChangeColors.LightAndDark, val), # val 为补间当前颜色，写入对应颜色因素。
		Color(2, 2, 2),
		Color(0.6, 0.6, 0.6),
		0.5
	)

## 明暗交替结束
func body_light_and_dark_end():
	if light_and_dark_tween and light_and_dark_tween.is_running():
		light_and_dark_tween.kill()
	set_other_color(E_ChangeColors.LightAndDark, Color(1,1,1))

## body被炸弹炸黑(蹦极)
func body_charred_black():
	set_other_color(E_ChangeColors.CharredBlack, Color(0,0,0))

## 模仿者更新材质
func imitater_update_material():
	material = IMITATER.duplicate()
	# 当前身体子节点，用于让对应的身体部件继承父级材质。
	for child in get_children():
		if child.owner == owner:
			GlobalUtils.node_use_parent_material(child)


#region 僵尸从地下\水下出现
## 僵尸从地下出来
## [param up_time] 身体从地下上浮到原高度的补间时长，单位为秒。
func zombie_body_up_from_ground(up_time:float = 1.0):
	body_mask_start()
	## 泥土特效
	var dirt_rise_effect:DirtRiseEffect = SceneRegistry.DIRT_RISE_EFFECT.instantiate()
	owner.add_child(dirt_rise_effect)
	dirt_rise_effect.start_dirt()

	pose_position.y += 100
	# 本次身体上浮的补间，将下移后的身体恢复到原高度，结束后关闭遮罩。
	var tween :Tween = create_tween()
	tween.tween_property(self, ^"pose_position:y", pose_position.y - 100.0, up_time)
	await tween.finished
	body_mask_end()

## 僵尸从水下出来(珊瑚僵尸)
func zombie_body_up_from_pool():
	body_mask_start()
	pose_position.y += 100
	# 本次身体上浮的补间，将下移后的身体恢复到原高度，结束后关闭遮罩。
	var tween :Tween = create_tween()
	tween.tween_property(self, ^"pose_position:y", pose_position.y - 100.0, 1.0)
	await tween.finished
	body_mask_end()

## 身体在当前body节点以上的显示,以下透明,需要转为画布坐标
func body_mask_start():
	material = BODY_MASK.duplicate()
	material.set_shader_parameter(&"cutoff_y", GlobalUtils.world_to_screen(owner.global_position).y)
	# 当前身体子节点，用于让对应的身体部件继承父级材质。
	for child in get_children():
		GlobalUtils.node_use_parent_material(child)

## 结束身体在当前body节点以上的显示,以下透明
func body_mask_end():
	material = null

#endregion

## 角色被压扁,复制一份body更新其为根节点父节点
## 角色被压扁时死亡消失,copy body保留两秒后消失
func be_flattened_body():
	# 压扁时保留的身体副本；脱离原角色节点后继续展示，再按自身逻辑释放。
	var body_copy = duplicate()
	owner.get_parent().add_child(body_copy)
	body_copy.copy_be_flattened()
	body_copy.global_position = global_position

## 复制体被压扁,两秒后删除
func copy_be_flattened():
	scale.y *= 0.4
	await_free(2)

## 设置等待一段时间后删除
## [param time] 节点释放前等待的秒数。
func await_free(time:float = 2):
	await get_tree().create_timer(time, false).timeout
	queue_free()
