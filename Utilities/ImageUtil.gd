## 图片辅助工具
## 提供不依赖扩展名匹配的稳健文件加载
class_name ImageUtil
extends RefCounted

## 按文件内容加载图片：先按扩展名快速加载，失败时按文件头回退重试常见格式
## 解决扩展名与实际格式不符（如 PNG 内容被命名成 .jpg）导致解码失败的问题
## 线程安全（Image.load_from_file / load_*_from_buffer 均为纯解码操作）
static func load_image_file(path: String) -> Image:
	if path.is_empty():
		return null
	var img := Image.load_from_file(path)
	if img and img.get_width() > 0 and img.get_height() > 0:
		return img
	# 扩展名未命中正确解码器时，读取字节按内容重试
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var buf_img := Image.new()
	if buf_img.load_png_from_buffer(bytes) == OK:
		return buf_img
	var buf_jpg := Image.new()
	if buf_jpg.load_jpg_from_buffer(bytes) == OK:
		return buf_jpg
	return null
