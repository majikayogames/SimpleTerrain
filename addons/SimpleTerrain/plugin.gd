@tool
extends EditorPlugin

const UTILS = preload("res://addons/SimpleTerrain/SimpleTerrainUtils.gd")

var undo_redo : EditorUndoRedoManager

var terrain_brush_container : Node
var terrain_brush : TerrainBrushDecal

var foliage_brush_container : Node
var foliage_brush : Node3D

var brush_toolbar : BrushToolbar
var foliage_brush_toolbar : FoliageBrushToolbar
var _left_mouse_pressed := false

func get_simple_terrain_selected() -> SimpleTerrain:
	if not Engine.is_editor_hint():
		return null
	var selected_nodes = EditorInterface.get_selection().get_selected_nodes()
	for node in selected_nodes:
		if node is SimpleTerrain:
			return node as SimpleTerrain
	return null

func get_simple_terrain_foliage_selected() -> SimpleTerrainFoliage:
	if not Engine.is_editor_hint():
		return null
	var selected_nodes = EditorInterface.get_selection().get_selected_nodes()
	for node in selected_nodes:
		if node is SimpleTerrainFoliage:
			return node as SimpleTerrainFoliage
	return null

func remove_brush_node_from_tree(): 
	update_brush_node(true)
	update_foliage_brush_node(true)
	
func update_brush_node(remove := false):
	var terrain := get_simple_terrain_selected()
	if brush_toolbar.get_brush_mode() == null or remove:
		terrain = null
	# Was freed when parent Terrain3D was freed
	if not is_instance_valid(terrain_brush_container) or terrain_brush_container == null:
		terrain_brush_container = Node.new()
		terrain_brush = TerrainBrushDecal.new()
		terrain_brush_container.add_child(terrain_brush)
	if terrain_brush_container.get_parent() != terrain:
		if terrain_brush_container.get_parent() != null:
			terrain_brush_container.get_parent().set_meta("_edit_lock_", null)
			terrain_brush_container.get_parent().remove_child(terrain_brush_container)
		if terrain != null:
			terrain.add_child(terrain_brush_container)
	terrain_brush.opacity = brush_toolbar.brush_opacity
	terrain_brush.brush_size = brush_toolbar.brush_size
	terrain_brush.hardness = brush_toolbar.brush_hardness
	terrain_brush.follow_mouse = true
	if not terrain_brush.is_inside_tree():
		terrain_brush.painting = false

func update_foliage_brush_node(remove := false):
	var foliage := get_simple_terrain_foliage_selected()
	if foliage_brush_toolbar.get_brush_mode() == null or remove:
		foliage = null
		
	# If we're removing it or no foliage is selected, clean up any existing brush
	if foliage == null and is_instance_valid(foliage_brush_container):
		if foliage_brush_container.get_parent() != null:
			foliage_brush_container.get_parent().remove_child(foliage_brush_container)
		return
	
	# Was freed when parent was freed or doesn't exist yet
	if not is_instance_valid(foliage_brush_container) or foliage_brush_container == null:
		foliage_brush_container = Node.new()
		foliage_brush = FoliageBrushDecal.new()
		foliage_brush_container.add_child(foliage_brush)
		
	# Only proceed if we have a valid foliage node and brush
	if foliage != null and is_instance_valid(foliage_brush):
		# Update parent if needed
		if foliage_brush_container.get_parent() != foliage:
			if foliage_brush_container.get_parent() != null:
				foliage_brush_container.get_parent().set_meta("_edit_lock_", null)
				foliage_brush_container.get_parent().remove_child(foliage_brush_container)
			foliage.add_child(foliage_brush_container)
		
		# Update brush properties
		foliage_brush.follow_mouse = true
		foliage_brush.undo_redo = undo_redo
		
		if foliage_brush_toolbar:
			foliage_brush.density = foliage_brush_toolbar.brush_density
			foliage_brush.brush_size = foliage_brush_toolbar.brush_size
			foliage_brush.randomness = foliage_brush_toolbar.brush_randomness
			
		if not foliage_brush.is_inside_tree():
			foliage_brush.painting = false

func _process(delta):
	update_brush_node()
	update_foliage_brush_node()

func _enter_tree():
	add_custom_type("SimpleTerrain", "Node3D", preload("SimpleTerrain.gd"), preload("res://addons/SimpleTerrain/assets/textures/terrain_icon.svg"))
	add_custom_type("SimpleTerrainFoliage", "Node3D", preload("SimpleTerrainFoliage.gd"), preload("res://addons/SimpleTerrain/assets/textures/foliage_icon.svg"))
	
	brush_toolbar = preload("res://addons/SimpleTerrain/BrushToolbar.tscn").instantiate()
	foliage_brush_toolbar = preload("res://addons/SimpleTerrain/FoliageBrushToolbar.tscn").instantiate()
	
	undo_redo = get_undo_redo()
	brush_toolbar.undo_redo = undo_redo
	foliage_brush_toolbar.undo_redo = undo_redo
	
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, brush_toolbar)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, foliage_brush_toolbar)

func _exit_tree():
	# Clean-up of the plugin goes here.
	remove_custom_type("SimpleTerrain")
	remove_custom_type("SimpleTerrainFoliage")
	# Remove the dock.
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, brush_toolbar)
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, foliage_brush_toolbar)
	# Erase the control from the memory.
	remove_brush_node_from_tree()
	terrain_brush_container.queue_free()
	foliage_brush_container.queue_free()
	brush_toolbar.free()
	foliage_brush_toolbar.free()

func _handles(object):
	return object is SimpleTerrain or object is SimpleTerrainFoliage

func _forward_3d_gui_input(camera, event):
	var left_mouse_pressed = false
	if event is InputEventMouse:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_left_mouse_pressed = event.pressed
				
	var terrain = get_simple_terrain_selected()
	var foliage = get_simple_terrain_foliage_selected()
	
	var terrain_brush_mode_selected = terrain and brush_toolbar.get_brush_mode() != null
	var foliage_brush_mode_selected = foliage and foliage_brush_toolbar.get_brush_mode() != null
	
	if terrain_brush_mode_selected:
		update_brush_node()
		if event is InputEventMouseMotion:
			terrain_brush._raycast_and_snap_to_terrain(camera, Vector2(event.position))
	else:
		remove_brush_node_from_tree()
	
	if foliage and foliage_brush_mode_selected:
		update_foliage_brush_node()
		if event is InputEventMouseMotion:
			foliage_brush._raycast_and_snap_to_terrain(camera, Vector2(event.position))
	else:
		update_foliage_brush_node(true)
	
	if _left_mouse_pressed and terrain_brush_mode_selected:
		var brush_mode = brush_toolbar.get_brush_mode()
		# Must create or convert the texture to an ImageTexture resource before painting on it
		UTILS.create_texture_if_necessary_before_paint(terrain, undo_redo, brush_mode)
		if not UTILS.is_texture_ready_for_edit(UTILS.get_texture_for_brush_mode(terrain, brush_mode)):
			_left_mouse_pressed = false
			brush_toolbar.show_convert_texture_popup(brush_mode)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		
		terrain_brush.undo_redo = undo_redo
		terrain_brush.painting = true
		terrain_brush.brush_mode = brush_toolbar.get_brush_mode()
	else:
		if terrain_brush:
			terrain_brush.painting = false
	
	if _left_mouse_pressed and foliage and foliage_brush_mode_selected:
		foliage_brush.painting = true
		foliage_brush.brush_mode = foliage_brush_toolbar.get_brush_mode()
	else:
		if foliage_brush:
			foliage_brush.painting = false
	
	# Only stop input propagation if actively using a brush
	if _left_mouse_pressed and (terrain_brush_mode_selected or foliage_brush_mode_selected):
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	else:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
