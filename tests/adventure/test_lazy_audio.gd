## Ensure cue catalogues stay metadata-only and every sound resolves on demand.
extends Node

func _ready() -> void:
	get_tree().create_timer(12.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()

func _run() -> void:
	var maps: Array[Dictionary] = [
		SoundManager.SFXBeAttackMap, SoundManager.SFXBulletMap,
		SoundManager.SFXCharacterMap, SoundManager.SFXCarzyDaveMap,
		SoundManager.SFXOtherMap]
	var count := 0
	for catalog: Dictionary in maps:
		for entry: Variant in catalog.values():
			var paths: Array = entry if entry is Array else [entry]
			for value: Variant in paths:
				if value == null:
					continue
				if not value is String or not ResourceLoader.exists(value, "AudioStream"):
					push_error("Invalid lazy SFX entry: %s" % str(value))
					get_tree().quit(1)
					return
				count += 1
	var first: String = SoundManager.SFXOtherMap[&"bleep"]
	SoundManager.play_other_SFX(&"bleep")
	var cache: Dictionary = SoundManager.get("_stream_cache")
	if not cache.has(first) or not cache[first] is AudioStream:
		push_error("SoundManager failed first-use stream cache")
		get_tree().quit(1)
		return
	var old: Resource = cache[first]
	SoundManager.play_other_SFX(&"bleep")
	if cache[first] != old:
		push_error("Repeated sound cue did not reuse stream")
		get_tree().quit(1)
		return
	SoundManager.play_be_attack_SFX(SoundManager.TypeBeAttackSFX.Null)
	print("PASS: lazy SFX catalogue, ", count, " cue paths; cache and no-op")
	get_tree().quit(0)
