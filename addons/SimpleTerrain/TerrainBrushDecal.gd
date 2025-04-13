@tool
class_name TerrainBrushDecal
extends Decal

const UTILS = preload("res://addons/SimpleTerrain/SimpleTerrainUtils.gd")
const BrushMode = UTILS.BrushMode

const PAINT_RATE_MS = 1000/60
var _last_paint_time = Time.get_ticks_msec()
@export var terrain : SimpleTerrain

var undo_redo : EditorUndoRedoManager

var colors := {
	BrushMode.RAISE: Color.WHITE,
	BrushMode.LOWER: Color.BLACK,
	BrushMode.SPLAT_0: Color.BLACK,
	BrushMode.SPLAT_1: Color.RED,
	BrushMode.SPLAT_2: Color.GREEN,
	BrushMode.SPLAT_3: Color.BLUE,
	BrushMode.SPLAT_TRANSPARENT: Color(0.0, 0.0, 0.0, 0.0),
}

@export var brush_mode := BrushMode.RAISE
var paint_texture := GradientTexture2D.new()

@export var follow_mouse := false
@export var painting := false

@export_range(0,1) var opacity := 1.0 :
	set(value):
		if opacity != value:
			opacity = value
			_update_textures()
@export_range(1,4096) var brush_size : int = 64 :
	set(value):
		if brush_size != value:
			brush_size = value
			_update_textures()
@export_range(0, 1) var hardness := 0.75 :
	set(value):
		if hardness != value:
			hardness = value
			_update_textures()

static func update_gradient_texture(gradient_tex : GradientTexture2D, size : int, opacity : float, hardness : float, marker : bool):
	gradient_tex.width = size
	gradient_tex.height = size
	gradient_tex.fill_from = Vector2(0.5, 0.5)
	gradient_tex.fill_to = Vector2(1.0, 0.5)
	gradient_tex.fill = GradientTexture2D.FILL_RADIAL
	if gradient_tex.gradient == null:
		gradient_tex.gradient = Gradient.new()
	gradient_tex.gradient.interpolation_color_space = Gradient.GRADIENT_COLOR_SPACE_LINEAR_SRGB
	gradient_tex.gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	while gradient_tex.gradient.get_point_count() > 1:
		gradient_tex.gradient.remove_point(0)
	if marker:
		# Visual effect on editor marker to show hardness
		# Sharp circle for hard, blurred large border for softened
		var diff = lerp(0.1, 0.4, 1.0 - hardness)
		gradient_tex.gradient.set_color(0, Color(1, 1, 1, opacity/7))
		gradient_tex.gradient.set_offset(0, 0.95 - diff)
		gradient_tex.gradient.add_point(0.95 - diff/2, Color(1, 1, 1, clampf(opacity, 0.25, 1.0)))
		gradient_tex.gradient.add_point(1.0, Color.TRANSPARENT)
	else:
		gradient_tex.gradient.set_color(0, Color(1, 1, 1, opacity))
		gradient_tex.gradient.set_offset(0, 0.0)
		gradient_tex.gradient.add_point(hardness * 0.9999, Color(1, 1, 1, opacity))
		gradient_tex.gradient.add_point(1.0, Color.TRANSPARENT)
	
func _update_textures():
	if texture_albedo == null:
		texture_albedo = GradientTexture2D.new()
	update_gradient_texture(texture_albedo, 256, opacity, hardness, true)
	update_gradient_texture(paint_texture, brush_size, opacity, hardness, false)
	_scale_decal_to_texture_size()

func _get_draw_color() -> Color:
	var color := Color.WHITE
	if brush_mode == BrushMode.FLATTEN:
		if terrain.heightmap_texture:
			var pos := _get_pos_on_texture(terrain.heightmap_texture)
			terrain.heightmap_texture.get_image().decompress()
			color = terrain.get_terrain_pixel(terrain.heightmap_texture, pos.x, pos.y)
	else:
		color = colors[brush_mode]
	return color

func _get_cur_terrain_map_texture() -> Texture2D:
	if not terrain:
		return null
	if brush_mode == BrushMode.RAISE or brush_mode == BrushMode.LOWER or brush_mode == BrushMode.FLATTEN:
		return terrain.heightmap_texture
	else:
		return terrain.splatmap_texture

func _get_pos_on_texture(texture : Texture2D) -> Vector2i:
	if not is_inside_tree() or not texture: return Vector2i(0,0)
	var norm_pos := terrain.get_global_pos_normalized_to_terrain(global_position)
	var to_px := Vector2(norm_pos.x, norm_pos.z) * Vector2(texture.get_image().get_size())
	return Vector2i(round(to_px.x),round(to_px.y))

func _scale_decal_to_texture_size():
	if not terrain: return
	var active_canvas = _get_cur_terrain_map_texture()
	var active_canvas_size := active_canvas.get_image().get_size() if active_canvas else Vector2i(1024,1024)
	var rel_size := Vector2(paint_texture.get_image().get_size()) / Vector2(active_canvas_size)
	var size_in_world_units = rel_size * terrain.get_total_size_without_height()
	self.size = Vector3(size_in_world_units.x, 50, size_in_world_units.y)

func blit_with_alpha_blending(from : Image, to : Image, pos : Vector2i, clamp : Color) -> void:
	var diff := Image.create(from.get_width(), from.get_height(), false, to.get_format())
	diff.fill(Color.BLACK)
	var destination_rect := Rect2i(pos, from.get_size())
	diff.blit_rect(to, destination_rect, Vector2i.ZERO)
	for x in diff.get_width():
		for y in diff.get_height():
			var brush_px := from.get_pixel(x, y)
			var clamped := brush_px.clamp(brush_px, clamp)
			if diff.get_format() == Image.FORMAT_RF:
				if brush_mode == BrushMode.FLATTEN:
					var lerped = lerp(diff.get_pixel(x, y).r, clamp.r, min(brush_px.a, clamp.a))
					diff.set_pixel(x, y, Color(lerped, 0, 0, 1))
				else:
					var cur_px = diff.get_pixel(x, y)
					if brush_mode == BrushMode.LOWER:
						var subtracted = cur_px.r - clamped.a / terrain.terrain_height_scale
						diff.set_pixel(x, y, Color(subtracted,0,0,1))
					else:
						var added = cur_px.r + clamped.r * clamped.a / terrain.terrain_height_scale
						diff.set_pixel(x, y, Color(added,0,0,1))
			else:
				var blended := diff.get_pixel(x, y).blend(clamped)
				blended.a = 1.0 if blended.a > 0.0001 else 0.0 # Incase painting back over hole
				diff.set_pixel(x, y, blended)
	to.blit_rect(diff, diff.get_used_rect(), pos)

# Limitation of Godot HeightmapShape3D/heightmaps in general probably: Corners are greedily filled by triangles.
# All bottom left and top right corners must be filled with a bottom or top triangle respectively.
# If we let the user punch out these corner triangles, Godot's collision map won't match.
# To do this, we must loop through all affected vertices positions, and check if they are a corner,
# Where corner = any empty square next to filled left/bottom or top/right squares.
# If we find a corner, we have must set the corner px to non transparent so it draws.
func fix_splatmap_jaggies_to_match_collision_shape(pos : Vector2i, diff : Image):
	var total_verts = terrain._get_num_verts_along_edge_total()
	var set_px_alpha_to_one : Callable = (func(xy : Vector2i, img : Image): img.set_pixelv(xy, img.get_pixelv(xy).clamp(Color(0,0,0,1),Color(1,1,1,1))))
	var splatmap_image := terrain.splatmap_texture.get_image()
	if splatmap_image.is_compressed(): splatmap_image.decompress()
	var one_px_in_quads := Vector2(splatmap_image.get_size() - Vector2i(1,1)) / Vector2(total_verts - 1, total_verts - 1)
	var one_quad_in_px := Vector2(total_verts - 1, total_verts - 1) / Vector2(splatmap_image.get_size() - Vector2i(1,1))
	var tl_tri_filled : Callable = func(x, z): return (
		splatmap_image.get_pixelv(Vector2i(Vector2(x,z) * one_px_in_quads)).a > 0.0001
		or splatmap_image.get_pixelv(Vector2i(Vector2(x + 1,z) * one_px_in_quads)).a > 0.0001
		or splatmap_image.get_pixelv(Vector2i(Vector2(x,z + 1) * one_px_in_quads)).a > 0.0001
	)
	var br_tri_filled : Callable = func(x, z): return (
		splatmap_image.get_pixelv(Vector2i(Vector2(x,z + 1) * one_px_in_quads)).a > 0.0001 # bl
		or splatmap_image.get_pixelv(Vector2i(Vector2(x + 1,z) * one_px_in_quads)).a > 0.0001 # tr
		or splatmap_image.get_pixelv(Vector2i(Vector2(x + 1,z + 1) * one_px_in_quads)).a > 0.0001 # br
	)
	var diff_rect := Rect2i(pos, diff.get_size())
	#diff_rect = diff_rect.grow(int(max(ceil(one_quad_in_px.x * 2), ceil(one_quad_in_px.y * 2))))
	# Loop thru all quads, - 1 is there b/c quads not verts
	for x in range(0, total_verts - 1):
		for z in range(0, total_verts - 1):
			var tl_px = Vector2i(Vector2(x, z) * one_px_in_quads)
			var br_px = Vector2i(Vector2(x + 1, z + 1) * one_px_in_quads)
			if not diff_rect.has_point(tl_px) and not diff_rect.has_point(br_px):
				continue
			if tl_tri_filled.call(x,z) and br_tri_filled.call(x,z):
				continue
			var tl := terrain._collision_shape_has_vert_at(x,z)
			var tr := terrain._collision_shape_has_vert_at(x+1,z)
			var br := terrain._collision_shape_has_vert_at(x+1,z+1)
			var bl := terrain._collision_shape_has_vert_at(x,z+1)
			# Any time the collision map will have a triangle, correct the render to match
			if tl and tr and bl:
				set_px_alpha_to_one.call(tl_px, splatmap_image)
			if br and tr and bl:
				set_px_alpha_to_one.call(br_px, splatmap_image)

func blit_hole_alpha_only(from : Image, to : Image, pos : Vector2i) -> void:
	var diff := Image.create(from.get_width(), from.get_height(), false, to.get_format())
	diff.fill(Color.BLACK)
	var destination_rect := Rect2i(pos, from.get_size())
	diff.blit_rect(to, destination_rect, Vector2i.ZERO)
	for x in diff.get_width():
		for y in diff.get_height():
			var original_px := diff.get_pixel(x, y)
			# Blit alpha as either one or zero since it's being used for painting holes
			if not is_equal_approx(from.get_pixel(x, y).a, 0.0):
				diff.set_pixel(x, y, Color(original_px.r, original_px.g, original_px.b, 0.0))
	to.blit_rect(diff, Rect2i(Vector2i(), diff.get_size()), pos)
	fix_splatmap_jaggies_to_match_collision_shape(pos, diff)

var _initial_paint_state : Image
var _paint_diff_rect := Rect2i(0,0,0,0)
var _was_painting_last_frame := false

func _before_paint_terrain():
	if not Engine.is_editor_hint() or not is_inside_tree(): return
	var tex := _get_cur_terrain_map_texture()
	if not tex: return
	var img := tex.get_image()
	img.decompress()
	# Save state of texture we're painting to
	_initial_paint_state = Image.create(img.get_width(), img.get_height(), false, img.get_format())
	_initial_paint_state.copy_from(img)
	# Reset the _paint_diff_rect
	_paint_diff_rect.size = Vector2i(0,0)

func _after_paint_terrain():
	var tex := _get_cur_terrain_map_texture()
	if not tex: return
	var img := tex.get_image()
	# Clip the initial state and paint diff by the _paint_diff_rect, save them both to images
	# Commit an item to undoredo with the area before and after the paint diff
	undo_redo.create_action("Paint terrain")
	undo_redo.add_do_method(terrain, "blit_to_texture", terrain, tex, img.get_region(_paint_diff_rect), _paint_diff_rect.position)
	undo_redo.add_undo_method(terrain, "blit_to_texture", terrain, tex, _initial_paint_state.get_region(_paint_diff_rect), _paint_diff_rect.position)
	_initial_paint_state = null
	# Commit but don't execute because we already painted
	undo_redo.commit_action(false)

func _paint_terrain():
	if not Engine.is_editor_hint() or not is_inside_tree(): return
	var tex := _get_cur_terrain_map_texture()
	if not tex: return
		
	var paint_pos = _get_pos_on_texture(tex) - Vector2i(paint_texture.get_size() / 2)
	tex.get_image().decompress()
	if brush_mode == BrushMode.SPLAT_TRANSPARENT:
		blit_hole_alpha_only(paint_texture.get_image(), tex.get_image(), paint_pos)
	else:
		blit_with_alpha_blending(paint_texture.get_image(), tex.get_image(), paint_pos, _get_draw_color())
	
	if not _paint_diff_rect.has_area():
		_paint_diff_rect = Rect2i(paint_pos, paint_texture.get_size())
	else:
		_paint_diff_rect = _paint_diff_rect.merge(Rect2i(paint_pos, paint_texture.get_size()))
	_paint_diff_rect = _paint_diff_rect.intersection(Rect2i(0,0,tex.get_width(), tex.get_height()))
	# Force update in editor
	tex.update(tex.get_image())
	terrain.update_normalmap_and_set_shader_parameter()

func is_on_terrain() -> bool:
	return self.is_inside_tree() and self.visible

func _raycast_and_snap_to_terrain(viewport_camera : Camera3D, mouse_position : Vector2):
	if not follow_mouse:
		self.visible = false
		return
	# Need to do an extra conversion in case the editor viewport is in half-resolution mode
	var viewport := viewport_camera.get_viewport()
	var viewport_container : Control = viewport.get_parent()
	var screen_pos = mouse_position * Vector2(viewport.size) / viewport_container.size
	
	var origin = viewport_camera.project_ray_origin(screen_pos)
	var dir = viewport_camera.project_ray_normal(screen_pos)
	var result = terrain.raycast_terrain_by_px(origin, dir * viewport_camera.far * 1.2)
	var hit_pos = result[0]
	if hit_pos != null:
		self.global_position = hit_pos
		self.visible = true
	else:
		self.visible = false
	
func _enter_tree():
	if not Engine.is_editor_hint(): return
	if $'..' is SimpleTerrain:
		terrain = $'..'
	elif $'../..' is SimpleTerrain:
		terrain = $'../..'
	_update_textures()

func _exit_tree():
	if _was_painting_last_frame:
		_after_paint_terrain()
		_was_painting_last_frame = false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if not Engine.is_editor_hint():
		return
	if painting and Time.get_ticks_msec() - _last_paint_time > PAINT_RATE_MS:
		if not _was_painting_last_frame:
			_before_paint_terrain()
			_was_painting_last_frame = true
		_paint_terrain()
		_last_paint_time = Time.get_ticks_msec()
	if not painting:
		if _was_painting_last_frame:
			_after_paint_terrain()
		_was_painting_last_frame = false
