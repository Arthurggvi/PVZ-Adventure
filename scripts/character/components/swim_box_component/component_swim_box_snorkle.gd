## 潜水僵尸仅订阅聚合后的水体接触变化，不重复维护接触计数。
extends SwimBoxComponent
class_name SwimBoxComponentBaseSnorkle

## [param swimming] 为是否仍接触任一水体；最后一次离开才播放出水水花。
func _on_water_contact_changed(swimming: bool) -> void:
	if not swimming:
		appear_splash()
	signal_change_is_swimming.emit(swimming)
