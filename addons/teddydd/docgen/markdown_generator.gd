## Saves docgen state as markdown files.
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
        
    ## Appends markdown header to the result.
	func _header(text, level=1):
		var r = ""
		for i in range(level):
			r += "#"
		r += " %s" % text
		result.append(r)
        
    ## Appends string or array of strings as paragraph to the result
	func _paragraph(arr):
		if typeof(arr) == TYPE_ARRAY:
			for l in arr:
				result.append(l)
		else: result.append(arr)
		result.append("")
        
    ## Append markdown quote to the result
	func _quote(text):
		result.append("> %s" % text)
		result.append("")
        
    ## appends GDScript source code as fenced code blocks
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
                
    ## appends array as unorered list
	func _list(arr, wrap=''):
		for e in arr:
			result.append("- %s%s%s" % [wrap, e, wrap])
		result.append("")