## 救主唤起的黑影；沿普通僵尸的行走路径移动，接触第一株植物或友方屏障后消散。
extends Zombie001Norm
class_name SaviorFollower

## 对普通植物送入生命组件的单次伤害。
const CONTACT_DAMAGE: int = 8000
## 路灯花承受的单次接触伤害。
const PLANTERN_DAMAGE: int = 50
## 普通植物检测层；黑影不会因魅惑僵尸或道具停下。
const PLANT_DETECTION_LAYER: int = 2
## 消散演出持续的游戏秒数，期间黑影已停止参与战斗。
const DISSOLVE_SECONDS: float = 0.54
## 身体瓦解材质，按世界坐标为普通僵尸的各个分件提供连续遮罩。
const DISSOLVE_SHADER: Shader = preload("res://shaders/adventure/wonderland/savior_follower_dissolve.gdshader")


## 保留普通僵尸的动画、移动与接触范围，只接入一次性植物伤害。
func _ready() -> void:
	super()
	modulate = Color.BLACK
	attack_component.set_physics_process(false)
	# 进家判定复用陆地受击层；水路的海草拖拽和清洁车可直接释放被检测对象，须关闭水路受击区。
	if curr_zombie_row_type == CharacterRegistry.ZombieRowType.Pool:
		hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	var detector: DetectComponent = attack_component.detect_component # 复用同行判断、受击范围及植物槽位优先级。
	detector.curr_collision_lay = PLANT_DETECTION_LAYER
	for area: Area2D in detector.all_ray_area: # 去掉普通僵尸的魅惑单位和道具索敌层。
		area.collision_mask = PLANT_DETECTION_LAYER
	detector.signal_can_attack.connect(_on_plant_contact)


## 返回是否接受战斗负面状态；黑影不会被植物的命中附带状态打断。
func can_receive_negative_effects() -> bool:
	return false


## 返回是否接受寒冷；原生全场冻结与减速入口共用此结果。
func can_receive_cold() -> bool:
	return false


## 黑影没有可以魅惑的本体，保持原来的敌我归属。
func be_hypno() -> void:
	pass


## 忽略原版投掷物附带的 [param _butter_time] 秒黄油定身。
func be_butter(_butter_time: float = 4.0) -> void:
	pass


## 忽略投射物附带的 [param _distance] 像素击退，按普通步态继续靠近植物。
func apply_projectile_knockback(_distance: float) -> void:
	pass


## [param _lawn_mover] 为尝试执行原生直接碾压的推车，黑影不进入其死亡演出。
func be_mowered_run(_lawn_mover: LawnMover) -> void:
	pass


## 拒绝不经生命组件的直接压扁。
func be_flattened() -> void:
	pass


## 即死攻击会绕过生命组件。只有显式清场可以从该入口移除信徒。
func character_death_disappear() -> void:
	if retiring_from_battle:
		super.character_death_disappear()


## 消散过程中若仍收到范围爆炸，保留既定退场演出。
func _preserves_blast_death_animation() -> bool:
	return true


## 对仍有效的首个接触目标扣血；同步锁定退场状态以防扣血回调重入。
func _on_plant_contact() -> void:
	var target: Character000Base = attack_component.detect_component.enemy_can_be_attacked # 禁用检测前保留本次目标。
	if is_death or not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion() \
			or not (target is Plant000Base or target is FriendlyBattleBarrier):
		return
	# 消散不产生可被复活的普通僵尸死亡记录，离树时由管理器注销。
	is_death = true
	attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	move_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	anim_component.stop_anim()
	swim_box_component.lock_swim_pose()
	_dissolve()
	var damage: int = PLANTERN_DAMAGE if target is Plant000Base and target.plant_type == CharacterRegistry.PlantType.P026Plantern \
		else CONTACT_DAMAGE # 仅结算一次接触伤害，不调用普通啃咬及其额外效果。
	if target is FriendlyBattleBarrier:
		target.note_contact(hurt_box_component.global_position.y - 30.0)
	target.be_attacked_bullet(damage, BulletRegistry.AttackMode.Penetration, true, false, 0, -1, null,
		CombatHitScope.for_plant_attack(self))


## 使定格的分件从脚部破碎并淡出；教堂投影图集同时读取根节点的透明度。
func _dissolve() -> void:
	var ink := ShaderMaterial.new() # 同一黑影的分件共享进度，其他黑影拥有独立材质。
	ink.shader = DISSOLVE_SHADER
	ink.set_shader_parameter(&"origin", global_position)
	ink.set_shader_parameter(&"clip_waterline", is_swimming)
	ink.set_shader_parameter(&"waterline_y", shadow.to_global(Vector2(0.0, swim_box_component.waterline_offset)).y)
	body.material = ink
	for child: Node in body.get_children(): # 仅把实际身体分件绑定到消散材质。
		if child is Node2D:
			GlobalUtils.node_use_parent_material(child)
	var fade: Tween = create_tween().set_parallel(true) # 停止战斗或切换场景时随黑影停止。
	var set_progress := func(progress: float) -> void: ink.set_shader_parameter(&"progress", progress) # 直接写共享进度，兼容没有 Shader 属性表的渲染后端。
	fade.tween_method(set_progress, 0.0, 1.0, DISSOLVE_SECONDS)
	fade.tween_property(body, ^"position:y", body.position.y - 12.0, DISSOLVE_SECONDS)
	fade.tween_property(self, ^"modulate:a", 0.0, DISSOLVE_SECONDS)
	fade.chain().tween_callback(queue_free)
