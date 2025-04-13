const HEIGHTMAP_FORMAT = Image.FORMAT_RF
const SPLATMAP_FORMAT = Image.FORMAT_RGBA8

enum BrushMode { RAISE, LOWER, FLATTEN, SPLAT_0, SPLAT_1, SPLAT_2, SPLAT_3, SPLAT_TRANSPARENT }
enum FoliageBrushMode { ADD, ADD_STACKED, REMOVE }

# Note: The web build was throwing an error for some reason if I didn't place EditorInterface
# references in a separate file.
static func get_editor_camera():
	# Running this directly crashes at runtime on web export so here's a workaround
	var script := GDScript.new()
	script.set_source_code("func eval(): return EditorInterface.get_editor_viewport_3d().get_camera_3d()" )
	script.reload()
	return script.new().eval()

static func bresenham_line_connect(a : Vector2i, b : Vector2i) -> Array[Vector2i]:
	var d := Vector2i(abs(b.x - a.x), -abs(b.y - a.y))
	var s := Vector2i(1 if a.x < b.x else -1, 1 if a.y < b.y else -1)
	var err : int = d.x + d.y
	var result := [] as Array[Vector2i]
	while true:
		result.push_back(a)
		if a == b: break
		if err*2 >= d.y:
			if a.x == b.x: break
			err += d.y;
			a.x += s.x
		if err*2 <= d.x:
			if a.y == b.y: break
			err += d.x
			a.y += s.y
	return result

# Convenience function to fallback to a 1x1 texture for flat terrain or default splat map.
static func get_image_texture_with_fallback(texture : Texture2D, fallback_color : Color) -> Texture:
	if texture != null and not texture is ImageTexture:
		# For noise textures and maybe others, they return null at _ready
		# So disabling fallback if it's not null
		return texture
	var img = texture.get_image() if texture else null
	if not img:
		var black_1x1 := Image.create(1,1,false,Image.FORMAT_RGBA8)
		black_1x1.fill(fallback_color)
		return ImageTexture.create_from_image(black_1x1)
	else:
		return texture

static func is_texture_ready_for_edit(texture : Texture2D) -> bool:
	if texture == null or not texture is ImageTexture:
		return false
	## TODO implement. Make sure texture is an image texture resource local to scene/saved
	return true

static func get_default_texture_size_for_terain(terrain : SimpleTerrain) -> Vector2i:
	return terrain._get_num_verts_along_edge_total()

static func get_texture_for_brush_mode(terrain : SimpleTerrain, brush_mode):
	if terrain == null:
		return null
	if brush_mode == BrushMode.RAISE or brush_mode == BrushMode.LOWER or brush_mode == BrushMode.FLATTEN:
		return terrain.heightmap_texture
	else:
		return terrain.splatmap_texture

# Note, leaving type off undo_redo for web bug where it throws error even if not used.
static func create_texture(terrain : SimpleTerrain, heightmap : bool, undo_redo, size := Vector2i()) -> void:
	if terrain == null: return
	if size.x == 0 or size.y == 0:
		size = get_default_texture_size_for_terain(terrain)
	var new_tex := ImageTexture.new()
	undo_redo.create_action("Create new terrain image")
	if heightmap:
		var img = Image.create(size.x, size.y, false, HEIGHTMAP_FORMAT)
		img.fill(Color.BLACK)
		new_tex.set_image(img)
		undo_redo.add_undo_property(terrain, "heightmap_texture", terrain.heightmap_texture)
		undo_redo.add_do_property(terrain, "heightmap_texture", new_tex)
	else:
		var img = Image.create(size.x, size.y, false, SPLATMAP_FORMAT)
		img.fill(Color.BLACK)
		print("Filled black")
		new_tex.set_image(img)
		undo_redo.add_undo_property(terrain, "splatmap_texture", terrain.splatmap_texture)
		undo_redo.add_do_property(terrain, "splatmap_texture", new_tex)
	undo_redo.commit_action()

static func create_texture_if_necessary_before_paint(terrain : SimpleTerrain, undo_redo, brush_mode : BrushMode):
	if terrain.splatmap_texture == null and (
		brush_mode == BrushMode.SPLAT_0
		or brush_mode == BrushMode.SPLAT_1
		or brush_mode == BrushMode.SPLAT_2
		or brush_mode == BrushMode.SPLAT_3
		or brush_mode == BrushMode.SPLAT_TRANSPARENT):
			create_texture(terrain, false, undo_redo)
	if terrain.heightmap_texture == null and (
		brush_mode == BrushMode.RAISE
		or brush_mode == BrushMode.LOWER
		or brush_mode == BrushMode.FLATTEN):
			create_texture(terrain, true, undo_redo)

static func get_point_y_on_plane(pt_on_plane : Vector2, a : Vector3, b : Vector3, c : Vector3) -> float:
	# Get the normal of the plane using cross product of two vectors on the plane
	var normal := (b - a).cross(c - a).normalized()
	if abs(normal.y) <= 0.00001:
		return a.y
	var d := -normal.dot(a)
	var y := -(normal.x * pt_on_plane.x + normal.z * pt_on_plane.y + d) / normal.y
	return y
