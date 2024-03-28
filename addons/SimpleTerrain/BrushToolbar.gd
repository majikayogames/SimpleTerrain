@tool
class_name BrushToolbar
extends MarginContainer

const UTILS = preload("res://addons/SimpleTerrain/SimpleTerrainUtils.gd")

var undo_redo : EditorUndoRedoManager

var brush_opacity : float = 1.0
func set_brush_opacity_from_ui(val):
	brush_opacity = float(val) / 100.0
	update_brush_preview()
var brush_size : int = 64
func set_brush_size_from_ui(val):
	brush_size = val
	update_brush_preview()
var brush_hardness : float = 0.75
func set_brush_hardness_from_ui(val):
	brush_hardness = float(val) / 100.0
	update_brush_preview()

func get_brush_mode():
	if %Raise.button_pressed:
		return UTILS.BrushMode.RAISE
	if %Lower.button_pressed:
		return UTILS.BrushMode.LOWER
	if %Flatten.button_pressed:
		return UTILS.BrushMode.FLATTEN
	if %Splat_0.button_pressed:
		return UTILS.BrushMode.SPLAT_0
	if %Splat_1.button_pressed:
		return UTILS.BrushMode.SPLAT_1
	if %Splat_2.button_pressed:
		return UTILS.BrushMode.SPLAT_2
	if %Splat_3.button_pressed:
		return UTILS.BrushMode.SPLAT_3
	if %Splat_Transparent.button_pressed:
		return UTILS.BrushMode.SPLAT_TRANSPARENT
	return null

func show_convert_texture_popup(brush_mode):
	var dialog : AcceptDialog = %ConvertTextureConfirmationDialog
	var texture_name :=  "Splatmap"
	if (brush_mode == UTILS.BrushMode.RAISE
		or brush_mode == UTILS.BrushMode.LOWER
		or brush_mode == UTILS.BrushMode.FLATTEN):
		texture_name = "Heightmap"
	%ConvertTextureConfirmationDialog.dialog_text = texture_name + " must duplicated and converted to an ImageTexture resource before editing."
	%ConvertTextureConfirmationDialog.show()

func get_simple_terrain_selected() -> SimpleTerrain:
	if not Engine.is_editor_hint():
		return null
	var selected_nodes = EditorInterface.get_selection().get_selected_nodes()
	for node in selected_nodes:
		if node is SimpleTerrain:
			return node as SimpleTerrain
	return null
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var terrain_selected := get_simple_terrain_selected()
	
	# Only show the toolbar and terrain settings popup when a SimpleTerrain node is selected.
	var selected_nodes = EditorInterface.get_selection().get_selected_nodes()
	if terrain_selected != null:
		self.visible = true
	else:
		self.visible = false
		#%SettingsPopup.hide()
	
	if terrain_selected != null:
		%HeightmapTextureRect.texture = terrain_selected.heightmap_texture
		%SplatmapTextureRect.texture = terrain_selected.splatmap_texture
	%HeightmapNoImageLabel.visible = %HeightmapTextureRect.texture == null
	%SplatmapNoImageLabel.visible = %SplatmapTextureRect.texture == null
	
	if terrain_selected != null:
		%ConvertToImageTextureHeightmap.disabled = (
			terrain_selected.heightmap_texture == null or terrain_selected.heightmap_texture is ImageTexture
		)
		%ConvertToImageTextureSplatmap.disabled = (
			terrain_selected.splatmap_texture == null or terrain_selected.splatmap_texture is ImageTexture
		)

func _on_settings_popup_visibility_changed():
	var terrain_selected := get_simple_terrain_selected()
	if terrain_selected == null: return
	
	if terrain_selected != null:
		var heightmap = terrain_selected.heightmap_texture
		var size := heightmap.get_size() if heightmap else UTILS.get_default_texture_size_for_terain(terrain_selected)
		%HeightmapWidth.value = size.x
		%HeightmapHeight.value = size.y
	if terrain_selected != null:
		var splatmap = terrain_selected.splatmap_texture
		var size := splatmap.get_size() if splatmap else UTILS.get_default_texture_size_for_terain(terrain_selected)
		%SplatmapWidth.value = size.x
		%SplatmapHeight.value = size.y

func _on_convert_to_image_texture_pressed(heightmap : bool):
	var terrain := get_simple_terrain_selected()
	if terrain == null: return
	var texture := terrain.heightmap_texture if heightmap else terrain.splatmap_texture
	
	undo_redo.create_action("Convert terrain image")
	
	var img := Image.new()
	img.copy_from(texture.get_image())
	img.clear_mipmaps()
	img.decompress()
	var new_image_texture := ImageTexture.new()
	if heightmap:
		img.convert(UTILS.HEIGHTMAP_FORMAT)
		new_image_texture.set_image(img)
		undo_redo.add_undo_property(terrain, "heightmap_texture", terrain.heightmap_texture)
		undo_redo.add_do_property(terrain, "heightmap_texture", new_image_texture)
	else:
		img.convert(UTILS.SPLATMAP_FORMAT)
		new_image_texture.set_image(img)
		undo_redo.add_undo_property(terrain, "splatmap_texture", terrain.splatmap_texture)
		undo_redo.add_do_property(terrain, "splatmap_texture", new_image_texture)
		
	undo_redo.commit_action()

func _on_new_image_pressed(heightmap : bool):
	var terrain := get_simple_terrain_selected()
	if terrain == null: return
	var new_tex := ImageTexture.new()
	undo_redo.create_action("Create new terrain image")
	if heightmap:
		var img = Image.create(%HeightmapWidth.value, %HeightmapHeight.value, false, UTILS.HEIGHTMAP_FORMAT)
		img.fill(Color.BLACK)
		new_tex.set_image(img)
		undo_redo.add_undo_property(terrain, "heightmap_texture", terrain.heightmap_texture)
		undo_redo.add_do_property(terrain, "heightmap_texture", new_tex)
	else:
		var img = Image.create(%SplatmapWidth.value, %SplatmapHeight.value, false, UTILS.SPLATMAP_FORMAT)
		img.fill(Color.BLACK)
		print("Filled black")
		new_tex.set_image(img)
		undo_redo.add_undo_property(terrain, "splatmap_texture", terrain.splatmap_texture)
		undo_redo.add_do_property(terrain, "splatmap_texture", new_tex)
	undo_redo.commit_action()

func _on_resize_image_pressed(heightmap : bool):
	var terrain := get_simple_terrain_selected()
	if terrain == null: return
	var texture = terrain.heightmap_texture if heightmap else terrain.splatmap_texture
	
	var img := Image.new()
	img.copy_from(texture.get_image())
	var new_tex := ImageTexture.new()
	undo_redo.create_action("Resize terrain image")
	if heightmap:
		img.resize(%HeightmapWidth.value, %HeightmapHeight.value)
		new_tex.set_image(img)
		undo_redo.add_undo_property(terrain, "heightmap_texture", terrain.heightmap_texture)
		undo_redo.add_do_property(terrain, "heightmap_texture", new_tex)
	else:
		img.resize(%SplatmapWidth.value, %SplatmapHeight.value)
		new_tex.set_image(img)
		undo_redo.add_undo_property(terrain, "splatmap_texture", terrain.splatmap_texture)
		undo_redo.add_do_property(terrain, "splatmap_texture", new_tex)
	undo_redo.commit_action()

func update_brush_preview():
	TerrainBrushDecal.update_gradient_texture(%BrushPreviewTextureRect.texture, 64, brush_opacity, brush_hardness, false)

func _on_create_collision_body_button_pressed():
	var terrain := get_simple_terrain_selected()
	if terrain == null: return
	if not terrain.has_collision_shape():
		undo_redo.create_action("Create collision shape")
		undo_redo.add_do_method(terrain, "create_collision_shape")
		undo_redo.add_undo_method(terrain, "remove_collision_shape")
		undo_redo.commit_action()
	else:
		terrain.create_collision_shape()

func _on_bake_normal_map_button_pressed():
	var terrain := get_simple_terrain_selected()
	if terrain == null: return
	var texture := terrain.update_normalmap_and_set_shader_parameter(true)
	# Ensure the viewport texture the baker gives us is updated.
	RenderingServer.frame_post_draw.connect((
		func():
			var new_normalmap_texture = ImageTexture.create_from_image(texture.get_image())
			undo_redo.create_action("Bake normal map")
			undo_redo.add_do_property(terrain, "normalmap_texture", new_normalmap_texture)
			undo_redo.add_undo_property(terrain, "normalmap_texture", terrain.normalmap_texture)
			undo_redo.commit_action()
	), CONNECT_ONE_SHOT)

func _on_convert_texture_confirmation_dialog_confirmed():
	_on_convert_to_image_texture_pressed(%ConvertTextureConfirmationDialog.dialog_text.begins_with("Heightmap"))
