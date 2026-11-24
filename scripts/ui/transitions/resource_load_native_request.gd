## 一条原生线程请求的状态；不持有窗口、场景或档案数据。
extends RefCounted
## 引擎请求的原始路径。
var path: String
## 请求开始时的单调时间，提供每个资源独立的三秒显示门槛。
var started_msec := Time.get_ticks_msec()
## 当前原生请求对应的持久化断点 ID。
var checkpoint_id := 0
## Godot 原生线程请求状态。
var status := ResourceLoader.THREAD_LOAD_IN_PROGRESS
## 已见到的最大进度。
var progress := 0.0
## 最近一次状态推进时间。
var advanced_at_msec := Time.get_ticks_msec()
## 最近一次查询时的渲染帧，避免重复轮询。
var polled_frame := -1
## 仍然观察本请求的批次数。
var observers := 0
## 已失效的请求不得被新批次复用。
var quarantined := false
## 是否已有无观察者回收定时器。
var reaping := false
## 当前回收已尝试次数。
var reap_passes := 0
## Godot 确认加载成功后取得的资源。
var resource: Resource
