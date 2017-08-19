#
## ## ## 
## doc: docken
## title: Simple documentation generator
## 
## 
## # Usage # H3
## `godot -s dockgen.gd`
##
## - normal comment
## normal text
## # h3 comment
## ## h4

extends SceneTree
## Version number. There is no backwords compability
const VERSION = 1

var dirs = {
	docs = "res://doc",
	scripts = []
}

func _init():
	"This function is executed when you exec script from commandline"
	prints("DOCKGEN v%s" % VERSION)
	prints("=============")
	scan_files("res://")
	create_doc_dir()
	
	for s in dirs.scripts:
		var st = proces(s)
		var rend = JSONRenderer.new(st)
		rend.generate_document()
		rend.save()
	quit()
	
func create_doc_dir():
	var dir = Directory.new()
	return dir.make_dir(dirs.docs)
	

## scan project directory for *.gd files and add them to dirs Dictionary
func scan_files(root):
	var dir = Directory.new()
	if dir.open(root) == OK:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while (file_name != ""):
			if not dir.current_is_dir() and file_name.extension() == "gd":
#				print("Found script: " + root  + file_name)
				dirs.scripts.append(root+file_name)
			elif dir.current_is_dir() and not file_name == ".." and not file_name == ".":
				scan_files(root+file_name+"/")
			file_name = dir.get_next()
	else:
		print("An error occurred when trying to access the path: %s" % root)

func proces(file):
	var f = File.new()
	f.open(file, File.READ)
	var state = {
		dir = dirs.docs,
		file = file,
		elements = []
	}
	var nextState = "parse_for_doc_enable"
	var line = ""
	if f.is_open():
#		prints("Check: %s" % file)
		while not f.eof_reached():
			if nextState == "end":
				break
			line = f.get_line()
			nextState = call(nextState, line, state)
	else:
		prints("An error occurred while loading file %s" % file)
	f.close()
	return state
	
## Look for `## doc: path/file.md` statement in file
## This must be top level statement on top of the file.
func parse_for_doc_enable(line, state):
	var tokens = line.split(" ")
	if tokens[0] == "##" and tokens.size() >= 2:
		if tokens[1] == "doc:":
			state.output = tokens[2]
			prints("Generating: %s => %s/%s" % [state.file, dirs.docs, state.output])
			return "parse_top_level"
	return "parse_for_doc_enable"
	
## Parse code looking for functions, class variables and inner classes.
## Takes indentation into account.
func parse_acc(line, state):
	var tokens = line.split(" ")
	if tokens.size() > 0:
		# top level comment - next line might be a function or variable
		if tokens[0] == "##":
			if tokens.size() > 1:
				append_or_create(state, "acc", collect(1, tokens))
			# empty comment
			else:
				# TODO: handle new line
				append_or_create(state, "acc", "")
			return "parse_acc"
	
## Parse header of script. Things like title, tool keyword, extends
## are parsed here. As soon as it reach extends it switch to contextual parsing
## therefore you should keep your main documentation before `extends` keyword.
func parse_top_level(line, state):
	var tokens = line.split(" ")
	if tokens.size() > 0:
		# top level documentation, no indentation
		if tokens[0] == "tool":
			state.elements.append({
				type = "tool",
				value = true
			})
			prints("ISTOOL")
			return "parse_top_level"
		if tokens[0] == "extends": # and tokens.size() == 2:
			state.elements.append({
				type = "extends",
				value = tokens[1]
			})
			prints("extends %s" % tokens[1])
			# everyting after extends is parsed with main routine
			return "parse_acc"
		elif tokens[0] == "##" and tokens.size() >= 2: 
			# special statement - title
			if tokens[1] == "title:":
				# collct rest of the title
				var title = collect(2, tokens)
				state.elements.append({
					type = "title",
					value = title
				})
				prints( "TITLE: %s" % title )
				return "parse_top_level"
			else:
				append_or_create(state, "file_documentation", collect(1, tokens) + "\n")
				return "parse_top_level"
	return "parse_top_level"
			
func parse_file_docs(line, state):
	var tokens = line.split(" ")
	if tokens[1] == "\t" or tokens[1] == "":
		pass # next element
	for i in range(tokens.size()):
		pass

## Create new element or append if previous
## has the same type.
func append_or_create(state, type, value):
	if state.elements.size() != 0:
		var prev = state.elements[state.elements.size()-1]
		prints("prev ", prev.type)
		if prev != null:
			if prev.type == type:
				prints("APPEND ")
				prev.value += value
				return
	prints("CREATE ")
	state.elements.append({
		type = type,
		value = value
	})

## Collect rest of tokens array as a string
## starts from given token (exclusive)
## default delimeter is a space
func collect(from, arr, delim=" "):
	var result = ""
	for i in range(from, arr.size()):
		result += str(arr[i], delim)
	return result
	
class JSONRenderer:
	var state
	var result
	func _init(state):
		self.state = state
	func get_file_name():
		return "%s/%s.json" % [ state.dir, state.output ]
	func generate_document():
		result = state.to_json()
	func save():
		var f = File.new()
		f.open(get_file_name(), File.WRITE)
		f.store_string(result)
		f.close()
	
		