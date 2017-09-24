## doc: docgen
## title: docgen - documentation generator for *GDScript*
## 
## This script allows to generate documentation form annotated GDScript files. Annotation format is
## really simple, it uses `##`.
## Suppored export formats are:
## - Markdown
## - json (for further processing)
##
## ## Usage
## Run from project directory:
## `godot -s dockgen.gd`
##
extends SceneTree

## Version number following [Semver specs](http://semver.org/)
const VERSION = "0.1"

## Setup allows you to customize behavoiur of docgen
# TODO - config in docgen_conf.gd
var setup = {
	output_dir = "res://doc",
	scripts = [],
	generators = [MarkdownGenerator, JSONGenerator]
}

## This function is executed when you exec `docgen.gd` script from command line.
func _init():
	prints("DOCGEN v%s" % VERSION)
	prints("=============")
	scan_files("res://")
	create_doc_dir()
	
	for s in setup.scripts:
		var st = proces(s)
		if st.output == null:
			continue
		for gen in setup.generators:
			var g = gen.new(st)
			prints("Generating: %s => %s" % [st.file, g.get_file_name()])
			g.generate_document()
			g.save()
	quit()
	
## Create doumentation directory
## It's `res://doc` by default
func create_doc_dir():
	var dir = Directory.new()
	return dir.make_dir(setup.output_dir)
	
## Scan project directory recursivly for *.gd files.
## Found files are added to scripts array in `setup` Dictionary
func scan_files(root):
	var dir = Directory.new()
	if dir.open(root) == OK:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while (file_name != ""):
			if not dir.current_is_dir() and file_name.extension() == "gd":
				setup.scripts.append(root+file_name)
			elif dir.current_is_dir() and not file_name == ".." and not file_name == ".":
				scan_files(root+file_name+"/")
			file_name = dir.get_next()
	else:
		print("An error occurred when trying to access the path: %s" % root)

## This function is called for every GDScript file found in project.
## If file contans `## doc: filename` instruction, documentation will be generated.
## Parsing pattern was inspired by [Rob Pike's](https://www.youtube.com/watch?v=HxaD_trXwRE&t=1529s)
## talk about writing lexers in Go.
func proces(file):
	var f = File.new()
	f.open(file, File.READ)
	var state = {
		dir = setup.output_dir,
		file = file,
		output = null,
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

#===================#
# Parsing functions #
#===================#

## Look for `## doc: path/file.md` statement in file
## This should be on top of the file. All documentation before
## this statement will be discarded.
func parse_for_doc_enable(line, state):
	var tokens = line.split(" ")
	if tokens[0] == "##" and tokens.size() >= 2:
		if tokens[1] == "doc:":
			state.output = tokens[2]
			return "parse_top_level"
	return "parse_for_doc_enable"
	
## Parse inner classes.
func parse_class(line, state):
	var st = state.elements.back()
	var tab = RegEx.new()
	# at lest one tab
	tab.compile("^\\t(.*)")
	if tab.find(line) != 0:
		st.type = "class"
		return "parse_acc"
	else:
		parse_acc(tab.get_capture(1), st)
		return "parse_class"
		
## Parse code looking for functions, class variables and inner classes.
## Acummulates result until top level declaration is found
## Documentation of given element (function/variable etc.)
## has to be written *before* that element.
func parse_acc(line, state):
	var tokens = line.split(" ")
	if tokens.size() > 0:
		# top level comment - next line might be a function or variable
		if tokens[0] == "##":
			if tokens.size() > 1:
				append_or_create(state, "acc", collect(1, tokens))
			else:
				# empty comment
				append_or_create(state, "acc", "")
			return "parse_acc"
		else:
			var test = match_top_level(line)
			if test != null:
				if test[1] == "var": 
					change_type_or_create(state, "acc", "variable", line, test[2])
				elif test[1] == "onready var": 
					change_type_or_create(state, "acc", "variable", line, test[2])
					state.elements.back().onready_var = true
				elif test[1] == "const":
					change_type_or_create(state, "acc", "constant", line, test[2])
				elif test[1] == "signal":
					change_type_or_create(state, "acc", "signal", line, test[2])
				elif test[1] == "func" or test[1] == 'static func':
					return parse_method(line, state)
				elif test[1] == "class":
					change_type_or_create(state, "acc", "class_acc", line, test[2])
					state.elements.back().elements = []
					return "parse_class"
			elif tokens[0].match("export*"):
				var test = match_export(line)
				change_type_or_create(state, "acc", "export", line, test[2])
				state.elements.back().editor_hint = test[1]
				state.elements.back().default_value = test[3]
			elif tokens[0] == "enum":
				return parse_enum_begin(line, state)
	return "parse_acc"
	
func parse_method(line, state):
	line = line.strip_edges()
	var test = match_method(line)
	change_type_or_create(state, "acc", "method", line, test[2])
	if test[1] == "static":
		state.elements.back().static_func = true
	if test[3] != "":
		var params = test[3].split(',')
		for i in range(params.size()):
			params[i] = params[i].strip_edges()
		if state.elements.back() != null:
			state.elements.back().params = params
	return "parse_acc"
	
func parse_enum_begin(line, state):
	var test = match_enum(line)
	# get name
	if test == null:
		return "parse_acc"
	var name = test[1]
	change_type_or_create(state, "acc", "enum_acc", line, name)
	state.elements.back().enums = []
	# get enums from first line
	if test[2] != "": # non empty first line
		var r = match_before_closing_brace(test[2])
		# cut last } if exist
		# find all enums in first line
		if r != null:
			for e in r[1].strip_edges().split(","):
				state.elements.back().enums.append( e.strip_edges() )
		if test[2].find("}") != -1: # found closing bracket
			change_type_or_create(state, "enum_acc", "enum", line, name)
			return "parse_acc"
	return "parse_enum_definition"
	
func parse_enum_definition(line,state):
	state.elements.back().signature += line
	var test = match_before_closing_brace(line)
	if test != null:
		if test[1] != "":
			for e in test[1].strip_edges().split(",", false):
				state.elements.back().enums.append(e.strip_edges())
	if line.find("}") != -1:
		change_type_or_create(state, "enum_acc", "enum", state.elements.back().signature, state.elements.back().name)
		return "parse_acc"
	return "parse_enum_definition"
	
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
				comment = ""
			})
			return "parse_top_level"
		if tokens[0] == "extends": # and tokens.size() == 2:
			state.elements.append({
				type = "extends",
				comment = tokens[1]
			})
			# everyting after extends is parsed with main routine
			return "parse_acc"
		if tokens[0] == "##" and tokens.size() >= 2:
			# special statement - title
			if tokens[1] == "title:":
				# collct rest of the title
				var title = collect(2, tokens)
				state.elements.append({
					type = "title",
					comment = title
				})
				return "parse_top_level"
			else:
				append_or_create(state, "file_documentation", collect(1, tokens))
				return "parse_top_level"
	return "parse_top_level"
			

#================#
# parser helpers #
#================#

## Create new element or append if previous
## has the same type.
func append_or_create(state, type, comment):
	if state.elements.size() != 0:
		var prev = state.elements[state.elements.size()-1]
		if prev != null:
			if prev.type == type:
				prev.comment.append(comment)
				return
	state.elements.append({
		type = type,
		comment = [comment]
	})
	
## If type of previous element equal param, it's changed to newtype
## otherwise new element is added with newtype. It's usefull
## when parser acumulates comments.
func change_type_or_create(state, type, newtype, signature, name):
	var prev = state.elements.back()
	if prev != null:
		if prev.type == type:
			prev.type = newtype
			prev.signature = signature
			prev.name = name
		else:
			state.elements.append({
				type = newtype,
				comment = [],
				signature = signature,
				name = name
			})
			
## Collect rest of tokens array as a string
## starts from given token (exclusive)
## default delimeter is a space
func collect(from, arr, delim=" "):
	var result = ""
	for i in range(from, arr.size()):
		result += str(arr[i], delim)
	return result

#=========#
# Regexes #
#=========#

func match_top_level(line):
	var reg = RegEx.new()
	reg.compile("^(static func|func|class|signal|var|onready var|const)\\s([\\w_-]+)(.+)?", 4)
	if reg.find(line) == 0:
		return Array(reg.get_captures())
	else: return null
	
## match export statement using regex
## returns caputre groups array or null
## - 0 - whole match
## - 1 - editor hint if any
## - 2 - name
## - 3 - default comment if any
func match_export(line):
	var reg = RegEx.new()
	reg.compile("export\\s?(?:\\((.+)\\))?\\svar\\s([\\w_-]+)(?:\\s?=([^#]+))?")
	if reg.find(line) == 0:
		return Array(reg.get_captures())
	else: return null
	
## Match enum definion
## Capture groups:
## - 0 - whole match
## - 1 - enum name if any
## - 2 - rest of the line without `{`, might be empty
func match_enum(line):
	var reg = RegEx.new()
	reg.compile("^enum\\s([\\w-_]+)?\\s?{(.+)?")
	if reg.find(line) == 0:
		return Array(reg.get_captures())
	else: return null
	
## Match open and close backet of enum definition
## Caputre groups:
## - 0 - whole match
## - 1 - { or empty
## - 2 - enum definition
## - 3 - } or empty
func match_enum_definiton(line):
	var reg = RegEx.new()
	reg.compile("({)(.+)(})")
	if reg.find(line) == 0:
		return Array(reg.get_captures())
	else: return null
	
func match_before_closing_brace(line):
	var reg = RegEx.new()
	reg.compile("([^}]+)}?")
	if reg.find(line) == 0:
		return Array(reg.get_captures())
	else: return null
	
## Checks if line has at leas one level of indentation.
## If that's true then returns line with removed first tabulation.
## Otherwise returns `null`
func match_indent(line):
	var tab = RegEx.new()
	tab.compile("^\\t(.*)")
	if tab.find(line) == 0:
		return tab.get_capture(1)
	else: return null
		
## Match function definiton
## Returns array of capture groups:
## - 0 - whole match
## - 1 - static or empty string
## - 2 - function name
## - 3 - params
func match_method(line):
	var reg = RegEx.new()
	reg.compile("(static\\s)?func\\s([\\w\\d_-]+)\\((.*)\\):")
	if reg.find(line) == 0:
		return Array(reg.get_captures())
	else: return null
	
#============#
# Generators #
#============#

class MarkdownGenerator:
	var state
	var result = []
	func _init(state):
		self.state = state
	func get_file_name():
		return "%s/%s.md" % [ state.dir, state.output ]
	func generate_document():
		# collect
		var title
		var ext
		var file_doc
		var sorted = {}
		for v in state.elements:
			if v.type == "title":
				title = v.comment
			elif v.type == "file_documentation":
				file_doc = v.comment
			elif v.type == "extends":
				ext = v.comment
			else:
				if not v.comment.empty():
					if not sorted.has(v.type):
						sorted[v.type] = []
					sorted[str(v.type)].append(v)
		
		# generate
		_header(title)
		_paragraph("%s - extends `%s`" % [title, state.file])
		_paragraph(file_doc)
		
		_section("Exports", "export", sorted)
		_section("Constants", "constant", sorted)
		_section("Variables", "variable", sorted)
		_section("Methods", "method", sorted)
	
	
	func save():
		var f = File.new()
		f.open(get_file_name(), File.WRITE)
		if not f.is_open():
			print("An error occurred when trying to create %s" % get_file_name())
		for l in result:
			f.store_line(l)
		f.close()
	func _header(text, level=1):
		var r = ""
		for i in range(level):
			r += "#"
		r += " %s" % text
		result.append(r)
		
	func _paragraph(arr):
		if typeof(arr) == TYPE_ARRAY:
			for l in arr:
				result.append(l)
		else: result.append(arr)
		result.append("")
		
	func _quote(text):
		result.append("> %s" % text)
		result.append("")
		
	func _src(arr):
		result.append("```gdscript")
		if typeof(arr) == TYPE_ARRAY:
			for l in arr:
				result.append(l)
		else: result.append(arr)
		result.append("```")
		
	func _section(name, key, dict):
		if dict.has(key):
			_header(name, 2)
			for v in dict[key]:
				if v.type == "method":
					var s = ''
					if v.has("static_func"):
						s += "**static**"
					s += v.name
					if v.has("params"):
						for p in v.params:
							s += " `%s`" % p
#						_header("Parameters", 4)
#						_list(v.params, "`")
					_header(s, 3)
				else:
					_header(v.name, 3)
				_paragraph(v.comment)
				
	func _list(arr, wrap=''):
		for e in arr:
			result.append("- %s%s%s" % [wrap, e, wrap])
		result.append("")

## Basic generator for docgen
## emits single markdown object witch is dump of parser state
## It's useful for debug but it might be used by external scripts to 
## generate different formats of documentation.
class JSONGenerator:
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