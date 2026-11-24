extends Node2D
## 地面端固定、飞船端跟随唯一飞艇枢轴的悬挂索具绘制层。
## 不从图片中平移旧缆绳；包络改变时仍须验证地表补底。
## 只使用相对世界坐标，避免相机缩放影响绳索锚点。
## 曲线由确定性的贝塞尔采样构成，无独立物理时间。
## 每次飞艇姿态改变只重画很少的线段。
## 飞艇枢轴的世界位置和旋转由主体组件提交。
var ship_pivot := Vector2.ZERO
## 该帧飞船实际偏移。
var offset := Vector2.ZERO
## 当前艇体旋转，弧度。
var roll := 0.0
## 原图中的三根系缆锚点，静态配置。
var records: Array = []
## 与原图同坐标的固定塔架前景遮挡图；不允许靠屏幕矩形猜测。
var occlusion: Image

## [param config] 来自art_layout.tethers；不修改原始点。
func configure(config: Dictionary, tower_occlusion: Image) -> void:
    records = config.get("tethers", [])
    occlusion = tower_occlusion
    var axis: Array = config["subjects"]["airship_body"]["pivot_world"] # 船本体唯一枢轴。
    ship_pivot = Vector2(axis[0],axis[1])
    queue_redraw()

## [param displacement] 为位置偏移；[param radians] 为艇体旋转弧度。
func set_pose(displacement: Vector2, radians: float) -> void:
    offset = displacement
    roll = radians
    queue_redraw()

## 一次绘制三根缆线；绘制节点由外部置于飞艇和背景之间。
func _draw() -> void:
    for record: Dictionary in records:
        var source: Array = record["ship_anchor"] # 移动端最初的世界位置。
        var target: Array = record["ground_anchor"] # 固定端，永远不变。
        var delta: Vector2 = Vector2(source[0],source[1])-ship_pivot
        var start: Vector2 = ship_pivot + delta.rotated(roll) + offset
        var finish: Vector2 = Vector2(target[0],target[1])
        var sag: float = float(record.get("sag_px",3.0))
        var points := PackedVector2Array() # 低成本分段曲线。
        for segment in range(49):
            var t: float = float(segment)/48.0 # 提高取样密度以匹配遮挡边缘。
            var bend: float = 4.0*t*(1.0-t)
            points.append(start.lerp(finish,t)+Vector2(sag*bend,4.0*bend))
        for segment in range(points.size()-1):
            var a: Vector2=points[segment] # 细分线段端点在地图世界坐标。
            var b: Vector2=points[segment+1]
            var center: Vector2i=Vector2i(((a+b)*0.5).floor())
            if occlusion != null and Rect2i(Vector2i.ZERO,occlusion.get_size()).has_point(center):
                if occlusion.get_pixelv(center).r>0.5:
                    continue # 真实塔架前景遮挡区不绘制悬索。
            draw_line(a,b,Color(0.20,0.16,0.12,0.80),1.2,true)
