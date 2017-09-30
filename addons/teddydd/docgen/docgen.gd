## doc: docgen
## title: docgen - documentation generator for *GDScript*
## 
## This script allows to generate documentation form annotated GDScript files. Annotation format is
## really simple, it uses `##` for meaningfull comment. Comment has to appear before commented element.
##
## Suppored export formats are:
## - Markdown
## - json (for further processing)
##
## ## Usage
## Run from project directory:
## `godot -s dockgen.gd`
## 
## Alternativly run from code:
## ```GDScript
## d = load("res://addons/teddydd/docgen.gd").new(setup)
## d.run()
## ```
extends Reference

var setup
var utils
var parsers

## Version number following [Semver specs](http://semver.org/)
var VERSION = 0.2

func _init(setup):
	self.setup = setup
	assert(typeof(self.setup) == TYPE_DICTIONARY)
	utils = load("res://addons/teddydd/docgen/file_scanner.gd").new()
	parsers = load("res://addons/teddydd/docgen/parser.gd").new()

func header():
	return """
		+========+
		| DocGen |
		+========+
		"""

func run():
	prints(header())
	prints("Version: %s" % VERSION)
	prints("-------------")
	
	utils.create_doc_dir(setup)
	setup.scripts = []
	utils.scan_files("res://", setup.scripts)
	
	for s in setup.scripts:
		var st = proces(s)
		if st.output == null:
			continue
		for gen in setup.generators:
			var g = gen.new(st)
			prints("Generating: %s => %s" % [st.file, g.get_file_name()])
			g.generate_document()
			g.save()
            
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
			nextState = parsers.call(nextState, line, state)
	else:
		prints("An error occurred while loading file %s" % file)
	f.close()
	return state