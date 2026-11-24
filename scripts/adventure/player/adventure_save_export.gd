## 安卓存档原样导出：Android 10+ 保存下载目录，并提供系统分享；无需助手或存储权限。
extends RefCounted
class_name AdventureSaveExport

## 游戏发布模板中已存在的 FileProvider，用于旧系统分享私有文件。
const FILE_PROVIDER: String = "io.github.arthurggvi.pvzadventure.fileprovider"

## 点击设置按钮后导出当前档案；返回界面提示，不修改存档原文件。
static func export_current() -> Dictionary:
	if not OS.has_feature("android"):
		return {"ok": false, "message": "请在安卓版游戏中导出存档。"}
	var source: String = "" # 保存成功后返回当前玩家的正式文件。
	if Global.save_service != null:
		source = Global.save_service.prepare_current_export_path() # 不依赖助手包或证书。
	if source.is_empty():
		return {"ok": false, "message": "请先进入有效存档，再尝试导出。"}
	var runtime = Engine.get_singleton("AndroidRuntime") # Godot 自带 Android Activity 入口。
	if runtime == null:
		return {"ok": false, "message": "暂时无法连接安卓系统。"}
	var activity = runtime.getActivity() # 当前游戏实例的 Activity。
	if activity == null:
		return {"ok": false, "message": "暂时无法连接安卓系统。"}
	var version = JavaClassWrapper.wrap("android.os.Build$VERSION") # 判定共享下载 API 是否可用。
	if version.SDK_INT >= 29:
		var saved: Dictionary = _save_to_downloads(activity, source) # 成功时保存持久文件。
		if saved.get("ok", false):
			var shared: bool = _start_share(activity, saved["uri"]) # 自动打开系统分享面板。
			return {"ok": true, "message": "存档已保存到下载文件夹。" if not shared else "已保存存档，请选择发送对象。"}
	# 系统下载功能不可用时，退回游戏原有的安全单文件分享，不要求玩家安装助手。
	var share_uri = _private_uri(activity, source) # 通过已有 FileProvider 暂时授权。
	if share_uri != null and _start_share(activity, share_uri):
		return {"ok": true, "message": "已打开分享菜单，请选择发送对象。"}
	return {"ok": false, "message": "存档导出失败，请重试。"}

## Android 10+ 通过 MediaStore 创建普通下载文件，不访问任何其他应用的目录。
static func _save_to_downloads(activity: Variant, path: String) -> Dictionary:
	var values_class = JavaClassWrapper.wrap("android.content.ContentValues") # 待发布文件元数据。
	var downloads = JavaClassWrapper.wrap("android.provider.MediaStore$Downloads") # 官方下载集合。
	var file_class = JavaClassWrapper.wrap("java.io.File") # 原始存档的绝对文件路径。
	var nio_files = JavaClassWrapper.wrap("java.nio.file.Files") # Android 8+ 标准字节复制。
	var values = values_class.ContentValues() # 每次点击生成独立的记录。
	var stamp: String = Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	var file_name: String = "PVZAdventure_" + stamp + ".json" # 避免暴露玩家账号名称。
	values.put("display_name", file_name)
	values.put("mime_type", "application/json")
	values.put("relative_path", "Download/PVZ-Adventure/")
	values.put("is_pending", 1)
	if JavaClassWrapper.get_exception() != null:
		return {"ok": false}
	var resolver = activity.getContentResolver() # 本游戏自己的内容解析器。
	var collection = downloads.getContentUri("external_primary") # 系统主共享存储。
	if collection == null or JavaClassWrapper.get_exception() != null:
		return {"ok": false}
	var uri = resolver.insert(collection, values) # IS_PENDING=1 时其他应用尚不可见。
	if uri == null or JavaClassWrapper.get_exception() != null:
		return {"ok": false}
	var completed: bool = false # 只有长度一致且发布成功才认定导出完成。
	var output = resolver.openOutputStream(uri) # Android 授权的目标文件句柄。
	if output != null and JavaClassWrapper.get_exception() == null:
		var original = file_class.File(path) # 源存档只读，不生成游戏目录之外的临时副本。
		var source = original.toPath() # API 26+ 的 Java Path。
		var copied = nio_files.copy(source, output) # 不经 GDScript 重编码，完整字节复制。
		var copy_exception = JavaClassWrapper.get_exception() # 记录复制失败，不被后续调用清除。
		output.flush()
		var flush_exception = JavaClassWrapper.get_exception() # 防止把写入失败误判成完成。
		output.close()
		var close_exception = JavaClassWrapper.get_exception() # 关闭失败也不发布文件。
		completed = copy_exception == null and flush_exception == null and close_exception == null \
			and int(copied) == int(original.length())
	if completed:
		var publish = values_class.ContentValues() # 提交前不会出现在系统下载列表。
		publish.put("is_pending", 0)
		completed = resolver.update(uri, publish, null, null) == 1
		completed = completed and JavaClassWrapper.get_exception() == null
	if not completed:
		resolver.delete(uri, null, null) # 任何失败都删除未提交的残留记录。
		return {"ok": false}
	return {"ok": true, "uri": uri}

## Android 9 或下载集合失败时，分享已有正式文件，系统自动授予接收者只读访问。
static func _private_uri(activity: Variant, path: String) -> Variant:
	var provider = JavaClassWrapper.wrap("androidx.core.content.FileProvider") # 发布模板已注册。
	var file_class = JavaClassWrapper.wrap("java.io.File") # Java File 对象只表示原档位置。
	var uri = provider.getUriForFile(activity, FILE_PROVIDER, file_class.File(path))
	if JavaClassWrapper.get_exception() != null:
		return null
	return uri

## 把真实 JSON 内容 URI 发给用户选择的聊天应用或文件管理应用。
static func _start_share(activity: Variant, uri: Variant) -> bool:
	if uri == null:
		return false
	var intent_class = JavaClassWrapper.wrap("android.content.Intent") # 安卓系统操作分发器。
	var clip_class = JavaClassWrapper.wrap("android.content.ClipData") # 提供单文件临时授权。
	var request = intent_class.Intent() # 不指定微信、QQ 或助手包名。
	request.setAction(intent_class.ACTION_SEND)
	request.setType("application/json")
	request.putExtra(intent_class.EXTRA_STREAM, uri)
	request.setClipData(clip_class.newRawUri("PVZ-Adventure 存档", uri))
	request.addFlags(intent_class.FLAG_GRANT_READ_URI_PERMISSION)
	var chooser = intent_class.createChooser(request, "发送存档给作者") # 使用系统原生分享面板。
	chooser.addFlags(intent_class.FLAG_GRANT_READ_URI_PERMISSION)
	activity.startActivity(chooser)
	return JavaClassWrapper.get_exception() == null
