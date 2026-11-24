## 单张 L8 世界索引图提供地区悬停身份；避免十一份全图 CPU 常驻副本。
## 空白像素为零，地区按 JSON 数组索引一至二百五十五，飞艇与码头使用同一地区。
## 索引图使用无损 PNG；如将来更换压缩格式，需先验证像素值身份不变。
extends RefCounted

## 一份解码结果服务全部地区悬停，不查询主体局部蒙版。
var index_image: Image
## 地标ID数组，元素顺序与构图配置保持一致。
var ids: Array[String] = []
## 索引图宽高，用于坐标裁切。
var world_size: Vector2i = Vector2i.ZERO

## [param assets] 已完成尺寸校验的资源仓库；返回能否安全交互。
func configure(assets: RefCounted) -> bool:
    var catalog: Dictionary = assets.landmarks # 地标显示ID与掩模按相同顺序。
    var atlas: Texture2D = ResourceLoader.load(assets.ROOT + str(catalog.get("hit_source", ""))) as Texture2D # 只取CPU索引，不加入地图纹理缓存。
    if atlas == null:
        return false
    index_image = atlas.get_image()
    world_size = Vector2i(assets.world_size())
    if index_image.get_size() != world_size or catalog.get("landmarks", []).size() > 255:
        push_error("Wonderland landmark ID atlas mismatch")
        return false
    ids.clear()
    for i in range(catalog["landmarks"].size()): # 数组顺序决定 L8 像素对应的地区身份。
        var entry: Dictionary = catalog["landmarks"][i] # 像素值与数组位置一一对应。
        ids.append(str(entry["id"]))
        var sample: Array = entry.get("hit_sample_world", []) # 每个地标的已知内部像素。
        if sample.size() != 2 or roundi(index_image.get_pixelv(Vector2i(sample[0],sample[1])).r*255.0) != i+1:
            push_error("Wonderland ID atlas import corrupt: " + str(entry["id"]))
            return false
    return true

## [param p] 是地图世界坐标；零值和越界位置没有悬停地区，不产生业务动作。
func static_hit(p: Vector2) -> String:
    var pixel: Vector2i = Vector2i(p.floor()) # 不能使用缩放后的屏幕坐标。
    if not Rect2i(Vector2i.ZERO, world_size).has_point(pixel):
        return ""
    var value: int = roundi(index_image.get_pixelv(pixel).r * 255.0) # L8 物件ID。
    if value < 1 or value > ids.size():
        return ""
    return ids[value - 1]
