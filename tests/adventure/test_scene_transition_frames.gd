## 按实际提交的渲染帧检查揭幕连续性，不截图、录屏或做审美判断。
extends Node

## 正式可复用过渡组件，测试不替换动画实现。
const TRANSITION = preload("res://scenes/ui/transitions/SceneTransition.tscn")
## 收集每个已呈现帧的遮幕强度，隐藏记为零。
var _samples: Array[float] = []
## 当前测试的真实组件。
var _transition: CanvasLayer

## 启动短时技术探针，断言失败后也会由超时明确退出。
func _ready() -> void:
	assert(OS.get_user_data_dir().contains("transition-frame-test"), "必须隔离 APPDATA")
	get_tree().create_timer(8.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()

## 模拟父场景同步加载超过动画时长，验证仍有真实中间渲染帧。
func _run() -> void:
	_transition = TRANSITION.instantiate()
	RenderingServer.frame_post_draw.connect(_sample_frame)
	add_child(_transition)
	# 复现目标场景资源加载或首帧准备停顿，不用动画期间的长时间视觉检查。
	OS.delay_msec(360)
	while _transition.busy:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.frame_post_draw.disconnect(_sample_frame)
	var intermediate := 0 # 真正呈现的渐变帧，排除纯黑和完全可见端点。
	for alpha: float in _samples: # 检查用户实际能看到的帧，不能仅验证 Tween 最终值。
		if alpha > 0.02 and alpha < 0.98:
			intermediate += 1
	print("Transition rendered alpha samples: ", _samples)
	assert(intermediate >= 4, "同步加载后揭幕缺少中间渲染帧，画面会从黑屏突然显现")
	print("PASS: slow scene readiness retains rendered intermediate reveal frames")
	get_tree().quit()

## 每个实际绘制帧记录一次，不读取或保存帧图像。
func _sample_frame() -> void:
	_samples.append(_transition.curtain.modulate.a if _transition.curtain.visible else 0.0)
