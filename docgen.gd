extends SceneTree

var docgen

## Setup allows you to customize behavoiur of docgen
# TODO - config in docgen_conf.gd
var setup = {
	output_dir = "res://doc",
	generators = [
		load("res://addons/teddydd/docgen/json_generator.gd").new().JSONGenerator
	]
}

## This function is executed when you exec `docgen.gd` script from command line.
func _init():
	docgen = load("res://addons/teddydd/docgen/docgen.gd") 
	var doc = docgen.new(setup)
	doc.run()


	# scan_files("res://")
	# create_doc_dir()
	
	# for s in setup.scripts:
	# 	var st = proces(s)
	# 	if st.output == null:
	# 		continue
	# 	for gen in setup.generators:
	# 		var g = gen.new(st)
	# 		prints("Generating: %s => %s" % [st.file, g.get_file_name()])
	# 		g.generate_document()
	# 		g.save()
	quit()