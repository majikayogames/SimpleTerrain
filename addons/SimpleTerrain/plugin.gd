@tool
extends EditorPlugin

const UTILS = preload("res://addons/SimpleTerrain/SimpleTerrainUtils.gd")

var undo_redo : EditorUndoRedoManager

var terrain_brush_container : Node
var terrain_brush : TerrainBrushDecal

var brush_toolbar : BrushToolbar
var _left_mouse_pressed := false

func get_simple_terrain_selected() -> SimpleTerrain:
	if not Engine.is_editor_hint():
		return null
	var selected_nodes = EditorInterface.get_selection().get_selected_nodes()
	for node in selected_nodes:
		if node is SimpleTerrain:
			return node as SimpleTerrain
	return null

func remove_brush_node_from_tree(): update_brush_node(true)
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
		
func _process(delta):
	update_brush_node()

func _enter_tree():
	add_custom_type("SimpleTerrain", "Node3D", preload("SimpleTerrain.gd"), preload("res://addons/SimpleTerrain/terrain_icon.svg"))
	brush_toolbar = preload("res://addons/SimpleTerrain/BrushToolbar.tscn").instantiate()
	undo_redo = get_undo_redo()
	brush_toolbar.undo_redo = undo_redo
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_BOTTOM , brush_toolbar)

func _exit_tree():
	# Clean-up of the plugin goes here.
	remove_custom_type("SimpleTerrain")
	# Remove the dock.
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, brush_toolbar)
	# Erase the control from the memory.
	remove_brush_node_from_tree()
	terrain_brush_container.queue_free()
	brush_toolbar.free()

func _handles(object):
	return object is SimpleTerrain
	
func _forward_3d_gui_input(camera, event):
	var left_mouse_pressed = false
	if event is InputEventMouse:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_left_mouse_pressed = event.pressed
				
	var terrain = get_simple_terrain_selected()
	if not terrain or brush_toolbar.get_brush_mode() == null:
		remove_brush_node_from_tree()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	else:
		update_brush_node()
	
	if event is InputEventMouseMotion:
		terrain_brush._raycast_and_snap_to_terrain(camera, Vector2(event.position))
	
	if _left_mouse_pressed:
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
		terrain_brush.painting = false
	
	if _left_mouse_pressed:
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	else:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
