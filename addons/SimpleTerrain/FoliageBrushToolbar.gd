@tool
class_name FoliageBrushToolbar
extends Control

const UTILS = preload("res://addons/SimpleTerrain/SimpleTerrainUtils.gd")

var undo_redo : EditorUndoRedoManager

var brush_randomness : float = 1.0
func set_brush_randomness_from_ui(val):
	brush_randomness = float(val) / 100.0
var brush_size : int = 64
func set_brush_size_from_ui(val):
	brush_size = val
var brush_density : float = 0.75
func set_brush_density_from_ui(val):
	brush_density = int(val)

func get_brush_mode():
	if %Add.button_pressed:
		return UTILS.FoliageBrushMode.ADD
	if %AddStacked.button_pressed:
		return UTILS.FoliageBrushMode.ADD_STACKED
	if %Remove.button_pressed:
		return UTILS.FoliageBrushMode.REMOVE
	return null

func _ready():
	if not Engine.is_editor_hint():
		queue_free()
		return
	
	# Set up selection changed callback
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	# Initial visibility check
	_on_selection_changed()

func _exit_tree():
	if Engine.is_editor_hint():
		if EditorInterface.get_selection().selection_changed.is_connected(_on_selection_changed):
			EditorInterface.get_selection().selection_changed.disconnect(_on_selection_changed)

func _on_selection_changed():
	var selected = EditorInterface.get_selection().get_selected_nodes()
	var should_show = false
	
	for node in selected:
		if node is SimpleTerrainFoliage:
			should_show = true
			break
	
	visible = should_show 

func get_simple_terrain_foliage_selected() -> SimpleTerrainFoliage:
	if not Engine.is_editor_hint():
		return null
	var selected_nodes = EditorInterface.get_selection().get_selected_nodes()
	for node in selected_nodes:
		if node is SimpleTerrainFoliage:
			return node as SimpleTerrainFoliage
	return null

func _on_recalculate_y_pressed() -> void:
	var foliage_node = get_simple_terrain_foliage_selected()
	if not foliage_node:
		print("No SimpleTerrainFoliage node selected to recalculate Y positions.")
		return

	if not foliage_node.multimesh:
		print("Selected Foliage node has no MultiMesh.")
		return
		
	if not undo_redo:
		print("UndoRedo manager not available.")
		return
	
	var changes = foliage_node.update_instance_heights()
	
	if changes.is_empty():
		#print("No height changes needed for ", foliage_node.name)
		return
	
	#print("Applying %d height changes with UndoRedo for: %s" % [changes.size(), foliage_node.name])
	
	undo_redo.create_action("Update Foliage Heights")
	
	var multimesh : MultiMesh = foliage_node.multimesh # For type hinting and clarity
	
	for change in changes:
		var index : int = change[0]
		var old_transform : Transform3D = change[1]
		var new_transform : Transform3D = change[2]
		
		# Register the 'do' action: set the new transform
		undo_redo.add_do_method(multimesh, "set_instance_transform", index, new_transform)
		# Register the 'undo' action: restore the old transform
		undo_redo.add_undo_method(multimesh, "set_instance_transform", index, old_transform)
		
	undo_redo.commit_action()
