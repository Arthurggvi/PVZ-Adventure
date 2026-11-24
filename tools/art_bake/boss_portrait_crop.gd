extends SceneTree
## Offline exact crop of existing imported boss atlas regions; no redrawing or lossy conversion.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for spec: Array in [
		["res://assets/adventure/zombies/cailleach/cailleach_idle_36f.png",Rect2i(77,24,178,178),"res://assets/adventure/zombies/cailleach/portrait.res"],
		["res://assets/adventure/zombies/savior/savior_atlas.png",Rect2i(58,34,124,124),"res://assets/adventure/zombies/savior/portrait.res"]]:
		var source: Texture2D=load(spec[0]) as Texture2D # 实际导入的原画；保留旧AtlasTexture使用的像素。
		assert(source!=null)
		var image: Image=source.get_image()
		if image.is_compressed():
			assert(image.decompress()==OK)
		var crop: Image=image.get_region(spec[1]) # 原头像矩形完全一致。
		var output: ImageTexture=ImageTexture.create_from_image(crop)
		assert(ResourceSaver.save(output,spec[2],ResourceSaver.FLAG_COMPRESS)==OK)
		var reread: Texture2D=ResourceLoader.load(spec[2],"Texture2D",ResourceLoader.CACHE_MODE_IGNORE)
		assert(reread.get_image().get_data()==crop.get_data())
		print("CROP_OK ",spec[2]," ",crop.get_size())
	quit()
