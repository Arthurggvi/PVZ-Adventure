extends SceneTree
## 离线无损发布原生贴图包：只读已批准源像素，正式运行无需Python或原始RGBA文件。
func _initialize() -> void:
	_publish.call_deferred()

func _publish() -> void:
	var request_path: String=OS.get_cmdline_user_args()[0] # 显式发布清单，不扫描用户文件。
	var request: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(request_path)) # 源/目标/所需资源。
	DirAccess.make_dir_recursive_absolute(str(request.output).path_join("textures"))
	var catalog := {} # 逻辑名到原生资源名。
	var evidence: Array[Dictionary]=[] # 每份保存重开检查结果。
	for logical: String in request.files:
		var source: String=str(request.source).path_join(logical) # 输入母图或技术场。
		var image: Image # 原尺寸和原数值，不重新生成图片。
		if logical.ends_with(".rgba32f"):
			var bytes := FileAccess.get_file_as_bytes(source) # 小端float32 H×W×RGBA。
			assert(bytes.size()==1672*941*16,source)
			image=Image.create_from_data(1672,941,false,Image.FORMAT_RGBAF,bytes)
		else:
			image=Image.load_from_file(source)
		assert(image!=null and not image.is_empty(),source)
		var texture := ImageTexture.create_from_image(image) # 序列化原生Texture2D。
		var name := "textures/"+logical.replace("/","__").replace(".","_")+".res" # 不依赖工作目录名称。
		var destination: String=str(request.output).path_join(name)
		assert(ResourceSaver.save(texture,destination,ResourceSaver.FLAG_COMPRESS)==OK,destination)
		var reread: Texture2D=ResourceLoader.load(destination,"Texture2D",ResourceLoader.CACHE_MODE_IGNORE) # 实际重开原生资源。
		assert(reread!=null and reread.get_image().get_data()==image.get_data(),logical)
		catalog[logical]=name
		evidence.append({"input":logical,"format":image.get_format(),"pixels_equal":true})
	var output := FileAccess.open(str(request.output).path_join("texture_catalog.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(catalog,"  "))
	output.close()
	output=FileAccess.open(str(request.report),FileAccess.WRITE)
	output.store_string(JSON.stringify({"texture_count":evidence.size(),"entries":evidence,"lossy_conversion":false},"  "))
	output.close()
	print("NATIVE_MENU_PACK_OK "+str(evidence.size()))
	quit(0)
