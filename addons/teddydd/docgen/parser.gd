extends Reference

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