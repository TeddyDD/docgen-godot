## doc: filescanner
## title: Docgen - file scanning utils

extends Reference
## Create doumentation directory
## It's `res://doc` by default
static func create_doc_dir(setup):
	assert(typeof(setup) == TYPE_DICTIONARY)
	var dir = Directory.new()
	return dir.make_dir(setup.output_dir)
	
## Scan project directory recursivly for *.gd files.
## Found files are added to scripts array in `setup` Dictionary
static func scan_files(root, scripts):
	var dir = Directory.new()
	if dir.open(root) == OK:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while (file_name != ""):
			if not dir.current_is_dir() and file_name.extension() == "gd":
				scripts.append(root+file_name)
			elif dir.current_is_dir() and not file_name == ".." and not file_name == ".":
				scan_files(root+file_name+"/", scripts)
			file_name = dir.get_next()
		return scripts
	else:
		print("An error occurred when trying to access the path: %s" % root)