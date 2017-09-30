## doc: JSON_Generator
## title: JSON Generator
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