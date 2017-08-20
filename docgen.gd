#
## ## ## 
## doc: docgen
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

var setup = {
	output_dir = "res://doc",
	scripts = [],
	renderers = [JSONRenderer]
}

func _init():
	"This function is executed when you exec script from commandline"
	prints("DOCGEN v%s" % VERSION)
	prints("=============")
	scan_files("res://")
	create_doc_dir()
	
	for s in setup.scripts:
		var st = proces(s)
		for renderer in setup.renderers:
			var rend = renderer.new(st)
			rend.generate_document()
			rend.save()
	quit()
	
## Create doumentation directory
## It's `res://doc` by default
func create_doc_dir():
	var dir = Directory.new()
	return dir.make_dir(setup.output_dir)
	
## scan project directory for *.gd files and add them to setup Dictionary
func scan_files(root):
	var dir = Directory.new()
	if dir.open(root) == OK:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while (file_name != ""):
			if not dir.current_is_dir() and file_name.extension() == "gd":
#				print("Found script: " + root  + file_name)
				setup.scripts.append(root+file_name)
			elif dir.current_is_dir() and not file_name == ".." and not file_name == ".":
				scan_files(root+file_name+"/")
			file_name = dir.get_next()
	else:
		print("An error occurred when trying to access the path: %s" % root)

func proces(file):
	var f = File.new()
	f.open(file, File.READ)
	var state = {
		dir = setup.output_dir,
		file = file,
		elements = []
	}
	var nextState = "parse_for_doc_enable"
	var line = ""
	if f.is_open():
		while not f.eof_reached():
			# Each parsing function call process one line of code.
			# Parsing function have to return next function to call or `end`
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
			prints("Generating: %s => %s/%s" % [state.file, setup.output_dir, state.output])
			return "parse_top_level"
	return "parse_for_doc_enable"
	
func parse_class(line, state):
	var st = state.elements.back()
#	prints(st)
	var tab = RegEx.new()
	# at lest one tab
	tab.compile("^\\t(.*)")
	if tab.find(line) != 0:
		st.type = "class"
		return "parse_acc"
	else:
		prints("in class parse line: %s" % tab.get_capture(1))
		parse_acc(tab.get_capture(1), st)
#		prints("found: %s" % st.elements.back().type)
		return "parse_class"
		
## Parse code looking for functions, class variables and inner classes.
## Takes indentation into account.
func parse_acc(line, state):
#	if state.elements.back().type == "class_acc":
#		var st = state.elements.back()
#	else: st == state
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
		else:
			var test = match_top_level(line)
			if test != null:
				if test[1] == "var": 
					append_signature_or_create(state, "acc", "variable", line, test[2])
				elif test[1] == "onready var": 
					append_signature_or_create(state, "acc", "variable", line, test[2])
					state.elements.back().onready_var = true
				elif test[1] == "const":
					append_signature_or_create(state, "acc", "constant", line, test[2])
				elif test[1] == "signal":
					append_signature_or_create(state, "acc", "signal", line, test[2])
				elif test[1] == "func":
					append_signature_or_create(state, "acc", "func", line, test[2])
				elif test[1] == "static func":
					append_signature_or_create(state, "acc", "func", line, test[2])
					state.elements.back().static_func = true
				elif test[1] == "class":
					append_signature_or_create(state, "acc", "class_acc", line, test[2])
					state.elements.back().elements = []
					return "parse_class"
			elif tokens[0] == "export":
					var test = match_export(line)
					append_signature_or_create(state, "acc", "export", line, test[2])
					state.elements.back().editor_hint = test[1]
					state.elements.back().default_valu31e = test[3]
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
		if tokens[0] == "##" and tokens.size() >= 2:
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
		if prev != null:
			if prev.type == type:
				prev.value.append(value)
				return
	state.elements.append({
		type = type,
		value = [value]
	})
	
func append_signature_or_create(state, type, newtype, signature, name):
	var prev = state.elements.back()
	if prev != null:
		if prev.type == type:
			prev.type = newtype
			prev.signature = signature
			prev.name = name
		else:
			state.elements.append({
				type = newtype,
				value = [],
				signature = signature,
				name = name
			})

func match_top_level(line):
	var reg = RegEx.new()
	reg.compile("^(static func|func|class|signal|var|onready var|const)\\s([\\w_-]+)(.+)?", 4)
#	if not reg.is_valid():
#		prints("ERROR: REGEX")
	if reg.find(line) == 0:
		return Array(reg.get_captures())
	else: return null
	
## match export statement using regex
## returns caputre groups array or null
## - 0 - whole match
## - 1 - editor hint if any
## - 2 - name
## - 3 - default value if any
func match_export(line):
	var reg = RegEx.new()
	reg.compile("^export(?:\\((.+)\\))?\\svar\\s([\\w_]+)(?:\\s?=)?([^#]+)")
	if reg.find(line) == 0:
		return Array(reg.get_captures())
	else: return null

## Collect rest of tokens array as a string
## starts from given token (exclusive)
## default delimeter is a space
func collect(from, arr, delim=" "):
	var result = ""
	for i in range(from, arr.size()):
		result += str(arr[i], delim)
	return result
	
## Basic renderer for docgen
## emits single markdown object witch is dump of parser state
## It's useful for debug but it might be used by external scripts to 
## generate different formats of documentation.
class JSONRenderer:
	var state
	var result
	## gets parser state at initialization
	func _init(state):
		self.state = state
	func get_file_name():
		return "%s/%s.json" % [ state.dir, state.output ]
	func generate_document():
		result = state.to_json()
	func save():
		var f = File.new()
		f.open(get_file_name(), File.WRITE)
		if not f.is_open():
			print("An error occurred when trying to create %s" % get_file_name())
		f.store_string(result)
		f.close()
