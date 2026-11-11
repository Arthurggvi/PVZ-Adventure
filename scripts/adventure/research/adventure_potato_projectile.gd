## 耦合发射的是独立土豆弹体，仅具有飞行和落点爆炸，不包含植物实例。
## 一次落点只结算一次；继承母雷快照的爆炸词条，不再生成下一代耦合弹体。
extends Node2D
class_name AdventurePotatoProjectile

const POTATO_TEXTURE = preload("res://assets/reanim/PotatoMine_body.png")
const FLIGHT_SECONDS: float = 0.52
const ARC_HEIGHT: float = 92.0

var _game: MainGameManager
var _start: Vector2
var _destination: Vector2
var _lane: int
var _blast: Dictionary
var _visual: BombEffectBase
var _elapsed: float = 0.0
var _impacted: bool = false

## [param game] 本局战场；[param origin] 弹体发射点；[param landing] 随机选中的格子中心。
## [param blast] 母雷已冻结的伤害、范围与击杀收益；[param visual] 原版爆炸特效的独立副本。
func launch(game: MainGameManager, origin: Vector2, landing: Vector2, lane: int,
		blast: Dictionary, visual: BombEffectBase) -> void:
	_game = game
	_start = origin
	_destination = landing
	_lane = lane
	_blast = blast.duplicate(true)
	_visual = visual
	var sprite := Sprite2D.new()
	sprite.texture = POTATO_TEXTURE
	sprite.scale = Vector2.ONE * 0.75
	sprite.z_index = 9
	add_child(sprite)
	if is_instance_valid(_visual):
		add_child(_visual)
		_visual.visible = false
	game.bullets.add_child(self)
	global_position = origin

func _process(delta: float) -> void:
	if _impacted:
		return
	_elapsed = minf(FLIGHT_SECONDS, _elapsed + delta)
	var phase: float = _elapsed / FLIGHT_SECONDS
	global_position = _start.lerp(_destination, phase) \
		+ Vector2(0.0, -sin(phase * PI) * ARC_HEIGHT)
	if phase >= 1.0:
		_impact()

## 到达落点才爆炸：移动过程不会生成、种植或触发任何植物。
func _impact() -> void:
	if _impacted:
		return
	_impacted = true
	if is_instance_valid(_game):
		if is_instance_valid(_visual) and is_instance_valid(_game.bombs):
			_visual.reparent(_game.bombs)
			_visual.global_position = _destination
			_visual.activate_bomb_effect()
		SoundManager.play_character_SFX(&"PotatoMine")
		AdventurePotatoExplosion.detonate.call_deferred(_game, _destination, _lane, _blast)
	queue_free()
