extends SceneTree
## Compila cada .gdshader del proyecto sin ventana. Los soaks corren
## --headless y pueden no compilar nunca un shader: cargarlo no basta, la
## compilación se dispara al pedir su lista de uniforms. Uso:
##
##     godot --headless --path . -s res://scenes/tests/shader_check.gd > shaders.log 2>&1
##     grep -nE "SHADER ERROR|Shader compilation failed" shaders.log
##
## Sin salida del grep = todos compilan. El código de salida de Godot NO
## sirve: un shader roto imprime su error y el proceso igual sale con 0.
## Un argumento extra después de `--` compila solo ese archivo (para probar
## que el chequeo de verdad detecta un shader roto):
##
##     godot --headless --path . -s res://scenes/tests/shader_check.gd -- /ruta/roto.gdshader

## Carpetas del proyecto que no se revisan.
const SKIPPED_DIRS: Array[String] = ["addons", "builds"]


func _initialize() -> void:
	var paths := PackedStringArray()
	for argument: String in OS.get_cmdline_user_args():
		paths.append(argument)
	if paths.is_empty():
		paths = _find("res://")
	for path: String in paths:
		# Un SHADER ERROR sale justo después de esta línea.
		print("Shader check: compiling %s" % path)
		var shader := _load_shader(path)
		if shader == null:
			push_error("Shader check: cannot load %s" % path)
			continue
		shader.get_shader_uniform_list()
	print("Shader check: compiled %d shader(s)" % paths.size())
	quit(0)


## Un shader del proyecto se carga como recurso; uno de fuera (la prueba del
## shader roto) se arma con el texto del archivo.
func _load_shader(path: String) -> Shader:
	if path.begins_with("res://"):
		return load(path) as Shader
	var code := FileAccess.get_file_as_string(path)
	if code.is_empty():
		return null
	var shader := Shader.new()
	shader.code = code
	return shader


func _find(dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == "gdshader":
			found.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		if sub.begins_with(".") or SKIPPED_DIRS.has(sub):
			continue
		found.append_array(_find(dir.path_join(sub)))
	return found
