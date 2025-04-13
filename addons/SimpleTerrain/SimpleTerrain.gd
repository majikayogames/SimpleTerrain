@tool
class_name SimpleTerrain
extends Node3D

const UTILS = preload("res://addons/SimpleTerrain/SimpleTerrainUtils.gd")

#########################
##     Editor vars     ##
#########################

## Whether to center the terrain or have its corner as its origin.
@export var centered := false :
	set(value): centered = value; _update_meshes()
## Create a StaticBody3D with a collision shape at runtime if it doesn't already exist
@export var use_collision := true
## LODs are created by subdividing a quad mesh 0-10 number of times. A value of 
## 3 here means the highest LOD means the highest resoluton will have 2 * (4^3)
## or 128 triangles per chunk. The highest LOD is also used for the heightmap's
## resolution.
@export_range(0,10) var highest_lod_resolution : int = 5 :
	set(value): highest_lod_resolution = value; _update_meshes()
## The subdivision level used for the heightmap collision shape.
@export_range(0,10) var collision_shape_resolution : int = 5
## Scales the width and depth of the meshes and collision shapes of the terrain.
@export var terrain_xz_scale : float = 64.0 :
	set(value): terrain_xz_scale = value; _update_meshes()
## The y positions of the terrain vertices will be between 0 and terrain_height_scale
## as long as it's a standard luminosity based heightmap.
## Note: Careful of setting this too high. The imprecisions of the heightmap texture will become obvious.
## Especially if using NoiseTexture2D, which only has 256 possible height values, the terrain will look blocky.
## It's better to set this to 1 and use the float format which is 32 bit, and has 16.7 million possible height values.
@export var terrain_height_scale : float = 1.0 :
	set(value): terrain_height_scale = value; _update_meshes()
## Number of chunks in the X and Z directions.
@export var chunk_count := Vector2i(16,16) :
	set(value): chunk_count = value.clamp(Vector2i(1,1), Vector2i(128,128)); _update_meshes()
## Number of LOD steps down per chunk away from camera. Can be fractional.
@export_range(0.0, 10.0) var lod_dropoff_rate : float = 0.25 :
	set(value): lod_dropoff_rate = value; _update_meshes()
	
@export_flags_3d_render var visual_instance_3d_layers: int = 1 :
	set(value):
		visual_instance_3d_layers = value;
		if is_inside_tree() and chunks_container:
			for chunk in chunks_container.get_children(true):
				if chunk is MeshInstance3D:
					chunk.layers = visual_instance_3d_layers

@export var lod_camera_override : Camera3D = null

## Toggle the debug wireframe texture
@export var debug_draw := false :
	set(value): debug_draw = value; _update_meshes()
	
## Toggle whether the normal map should be updated every frame.
## Added this because normal map doesn't update when changing NoiseTexture2D parameters.
@export var update_normal_map_every_frame_in_editor := true

## Debug toggle for debug mesh view. If on, always default to use editor viewport cam.
## Otherwise, will try to use Camera3D node if found in scene.
@export var always_use_editor_cam := true

@export_group("Textures")
## Heightmap texture sampled to create the terrain.
## Note: The size dimensions of this texture should match the number of vertices.
## The proper size can be found by clearing the heightmap, and using the default size in the terrain settings popup menu.
@export var heightmap_texture : Texture2D :
	set(value): heightmap_texture = value; _update_meshes()
@export var splatmap_texture : Texture2D :
	set(value): splatmap_texture = value; _update_meshes()
## Normalmap Texture. Can be baked in. Not sure if worth it to do ever. Otherwise just generates once at runtime via a shader.
@export var normalmap_texture : Texture2D :
	set(value): normalmap_texture = value; _update_meshes()

@export_subgroup("Texture 0")
@export var texture_0_albedo : Texture2D :
	set(value): texture_0_albedo = value; _update_meshes()
@export var texture_0_normal : Texture2D :
	set(value): texture_0_normal = value; _update_meshes()
@export var texture_0_uv_scale := Vector2(10,10) :
	set(value): texture_0_uv_scale = value; _update_meshes()
@export var enable_triplanar_on_texture_0 : bool = true :
	set(value): enable_triplanar_on_texture_0 = value; _update_meshes()

@export_subgroup("Texture 1")
@export var texture_1_albedo : Texture2D :
	set(value): texture_1_albedo = value; _update_meshes()
@export var texture_1_normal : Texture2D :
	set(value): texture_1_normal = value; _update_meshes()
@export var texture_1_uv_scale := Vector2(10,10) :
	set(value): texture_1_uv_scale = value; _update_meshes()
@export var enable_triplanar_on_texture_1 : bool = false :
	set(value): enable_triplanar_on_texture_1 = value; _update_meshes()

@export_subgroup("Texture 2")
@export var texture_2_albedo : Texture2D :
	set(value): texture_2_albedo = value; _update_meshes()
@export var texture_2_normal : Texture2D :
	set(value): texture_2_normal = value; _update_meshes()
@export var texture_2_uv_scale := Vector2(10,10) :
	set(value): texture_2_uv_scale = value; _update_meshes()
@export var enable_triplanar_on_texture_2 : bool = false :
	set(value): enable_triplanar_on_texture_2 = value; _update_meshes()

@export_subgroup("Texture 3")
@export var texture_3_albedo : Texture2D :
	set(value): texture_3_albedo = value; _update_meshes()
@export var texture_3_normal : Texture2D :
	set(value): texture_3_normal = value; _update_meshes()
@export var texture_3_uv_scale := Vector2(10,10) :
	set(value): texture_3_uv_scale = value; _update_meshes()
@export var enable_triplanar_on_texture_3 : bool = false :
	set(value): enable_triplanar_on_texture_3 = value; _update_meshes()


#######################
##     Resources     ##
#######################

const TERRAIN_SHADER = preload("res://addons/SimpleTerrain/Shaders/SimpleTerrain.gdshader")
const NORMAL_MAP_BAKER_SCENE : PackedScene = preload("res://addons/SimpleTerrain/NormalMapBaker.tscn")

#################
## Script vars ##
#################

const XZ = Vector3(1,0,1)
const ONE_HALF_XZ = Vector3(0.5, 0, 0.5)

var lod_meshes := [] as Array[QuadMesh]
var chunks := [] as Array[Array]
var shader_material := ShaderMaterial.new()

var chunks_container := Node3D.new()

var normal_map_baker = null

# Only loaded in if debug draw is enabled
var debug_shader = null

# Box collision shape so SimpleTerrain node can be selected in editor
var _editor_csg_box = null

#######################
## Utility functions ##
#######################

## Used for undo and redo painting behavior. Editor undo redo needs method on object that owns undo/redo stack
func blit_to_texture(terrain : SimpleTerrain, texture : Texture2D, image : Image, pos : Vector2i):
	texture.get_image().blit_rect(image, image.get_used_rect(), pos)
	texture.update(texture.get_image())
	terrain.update_normalmap_and_set_shader_parameter()

## Raycasts via pixel checks. Returns the global position of the ray hit if there is one.
## Returns in the format [global pos : Vector3, splatmap : Color] or [null, null] if it doesn't hit.
func raycast_terrain_by_px(ray_start_global_position : Vector3, target_position_relative : Vector3, snap_to_px := true) -> Array:
	var start_pos = get_global_pos_normalized_to_terrain(ray_start_global_position)
	var end_pos = get_global_pos_normalized_to_terrain(ray_start_global_position + target_position_relative)
	# Put in pixel space
	var heightmap_size := heightmap_texture.get_size() if heightmap_texture else Vector2(UTILS.get_default_texture_size_for_terain(self))
	var splatmap_or_fallback := UTILS.get_image_texture_with_fallback(splatmap_texture, Color.BLACK)
	var start_pos_px := Vector2i(Vector2(start_pos.x, start_pos.z) * (heightmap_size - Vector2(1,1)))
	var end_pos_px := Vector2i(Vector2(end_pos.x, end_pos.z) * (heightmap_size - Vector2(1,1)))
	var connecting_px := UTILS.bresenham_line_connect(start_pos_px, end_pos_px)
	if connecting_px.size() == 1: # Make sure ray has at least 2 points for ray height interpolation
		connecting_px.push_back(connecting_px.back())
	for i in len(connecting_px):
		var px := connecting_px[i]
		if not Rect2i(0,0,heightmap_size.x,heightmap_size.y).has_point(px):
			continue
		var pct_along_ray := float(i) / float(len(connecting_px) - 1)
		var ray_height : float = lerp(start_pos.y, end_pos.y, pct_along_ray)
		var color := get_terrain_pixel(heightmap_texture, px.x, px.y)
		#print(color)
		if ray_height <= color.r:
			var splat_color := Color.BLACK
			if splatmap_texture != null:
				var splat_px = Vector2(px) * heightmap_size / splatmap_texture.get_size()
				splat_color = get_terrain_pixel(splatmap_texture, int(splat_px.x), int(splat_px.y))
			var world_xz := Vector2(px) / (heightmap_size - Vector2(1,1)) * get_total_size_without_height()
			var hit_global_pos = chunks_container.global_transform * Vector3(world_xz.x, color.r * terrain_height_scale, world_xz.y)
			#print(hit_global_pos)
			return [hit_global_pos, splat_color]
	return [null, null]
	
func get_global_pos_normalized_to_terrain(global_pos : Vector3) -> Vector3:
	return (chunks_container.global_transform.affine_inverse() * global_pos) / get_total_size()

func get_terrain_pixel(tex : Texture2D, x : int, y : int, fallback_color := Color.TRANSPARENT) -> Color:
	if tex == null or tex.get_image() == null:
		return fallback_color
	if (x < 0 or y < 0 or x >= _get_texture_size(tex).x or y >= _get_texture_size(tex).y):
		return fallback_color
	return tex.get_image().get_pixel(x, y)
	
func _get_texture_size(tex : Texture2D) -> Vector2i:
	if tex == null or tex.get_image() == null:
		return Vector2i(0,0)
	return tex.get_image().get_size()

func get_total_size_without_height() -> Vector2:
	return Vector2(chunk_count) * terrain_xz_scale

func get_total_size() -> Vector3:
	return Vector3(chunk_count.x, 0, chunk_count.y) * terrain_xz_scale + Vector3(0,terrain_height_scale,0)

func _get_corner_point_global_pos() -> Vector3:
	return chunks_container.global_position

func _get_num_verts_along_chunk_edge(lod=null) -> int:
	if lod == null:
		lod = len(lod_meshes) - 1
	var num_segments_per_chunk = pow(2, lod)
	return num_segments_per_chunk + 1

## If lod passed is null it uses the highest_lod_resolution in _get_num_verts_along_chunk_edge
func _get_num_verts_along_edge_total(lod=null) -> Vector2i:
	var along_x = (_get_num_verts_along_chunk_edge(lod) - 1) * chunk_count.x + 1
	var along_z = (_get_num_verts_along_chunk_edge(lod) - 1) * chunk_count.y + 1
	return Vector2i(along_x, along_z)

func _get_chunk_subdivs_for_lod(lod : int) -> int:
	return pow(2, lod) - 1

func _get_cur_camera() -> Camera3D:
	var cur_camera : Camera3D = null
	if get_viewport() and get_viewport().get_camera_3d():
		cur_camera = get_viewport().get_camera_3d()
	if lod_camera_override != null:
		cur_camera = lod_camera_override
	if not cur_camera or not is_instance_valid(cur_camera) or not cur_camera.is_inside_tree():
		if Engine.is_editor_hint():
			cur_camera = UTILS.get_editor_camera()
	if Engine.is_editor_hint() and always_use_editor_cam:
			cur_camera = UTILS.get_editor_camera()
	return cur_camera

func _get_camera_location_rel() -> Vector3:
	var cam := _get_cur_camera()
	if cam == null:
		return Vector3.ZERO
	return chunks_container.global_transform.affine_inverse() * cam.global_position
	
func _get_camera_location_in_chunks() -> Vector3i:
	var cam_pos_rel := _get_camera_location_rel()
	cam_pos_rel /= Vector3(terrain_xz_scale, terrain_xz_scale * 2.0, terrain_xz_scale)
	return Vector3i(cam_pos_rel)

#################################
##  Terrain update functions   ##
#################################

func update_normalmap_and_set_shader_parameter() -> Texture2D:
	var heightmap_or_fallback := UTILS.get_image_texture_with_fallback(heightmap_texture, Color.BLACK)
	var normal_or_generate = normalmap_texture
	if normal_or_generate == null:
		if normal_map_baker == null:
			normal_map_baker = NORMAL_MAP_BAKER_SCENE.instantiate()
			add_child(normal_map_baker)
			#normal_map_baker.owner = get_tree().edited_scene_root
		var quad_size = get_total_size().x / (_get_num_verts_along_edge_total().x - 1)
		normal_or_generate = normal_map_baker.render_normalmap(heightmap_or_fallback, terrain_height_scale, quad_size)
	shader_material.set_shader_parameter("normalmap", normal_or_generate)
	return normal_or_generate

## non_const_only is for only updating the camera pos & terrain transform, don't have to send all textures to GPU each frame
func update_shader_params(non_const_only := false):
	shader_material.set_shader_parameter("cam_rel_pos", _get_camera_location_rel())
	shader_material.set_shader_parameter("cam_chunk_loc", _get_camera_location_in_chunks())
	# https://paroj.github.io/gltut/Illumination/Tut09%20Normal%20Transformation.html
	# The inverse tranpose ends up being the same rotation but inverted scale (1/scale)
	shader_material.set_shader_parameter("inv_normal_basis", chunks_container.global_transform.basis.inverse().transposed())
	shader_material.set_shader_parameter("inv_global_transform", chunks_container.global_transform.affine_inverse())
	
	if non_const_only:
		return
	
	if debug_draw:
		if debug_shader == null:
			debug_shader = load("res://addons/SimpleTerrain/Shaders/DebugShader.gdshader")
		shader_material.shader = debug_shader
	else:
		shader_material.shader = TERRAIN_SHADER

	update_normalmap_and_set_shader_parameter()
	
	shader_material.set_shader_parameter("heightmap",
		UTILS.get_image_texture_with_fallback(heightmap_texture, Color.BLACK))
	shader_material.set_shader_parameter("splatmap",
		UTILS.get_image_texture_with_fallback(splatmap_texture, Color.BLACK))
	shader_material.set_shader_parameter("texture_0_albedo", texture_0_albedo)
	shader_material.set_shader_parameter("texture_1_albedo", texture_1_albedo)
	shader_material.set_shader_parameter("texture_2_albedo", texture_2_albedo)
	shader_material.set_shader_parameter("texture_3_albedo", texture_3_albedo)
	
	shader_material.set_shader_parameter("texture_0_normal",
		UTILS.get_image_texture_with_fallback(texture_0_normal, Color(0.5, 0.5, 1.0)))
	shader_material.set_shader_parameter("texture_1_normal",
		UTILS.get_image_texture_with_fallback(texture_1_normal, Color(0.5, 0.5, 1.0)))
	shader_material.set_shader_parameter("texture_2_normal",
		UTILS.get_image_texture_with_fallback(texture_2_normal, Color(0.5, 0.5, 1.0)))
	shader_material.set_shader_parameter("texture_3_normal",
		UTILS.get_image_texture_with_fallback(texture_3_normal, Color(0.5, 0.5, 1.0)))
	
	shader_material.set_shader_parameter("texture_0_uv_scale", texture_0_uv_scale)
	shader_material.set_shader_parameter("texture_1_uv_scale", texture_1_uv_scale)
	shader_material.set_shader_parameter("texture_2_uv_scale", texture_2_uv_scale)
	shader_material.set_shader_parameter("texture_3_uv_scale", texture_3_uv_scale)

	shader_material.set_shader_parameter("chunk_count", chunk_count)
	shader_material.set_shader_parameter("terrain_xz_scale", terrain_xz_scale)
	shader_material.set_shader_parameter("terrain_height_scale", terrain_height_scale)
	shader_material.set_shader_parameter("highest_lod_res", highest_lod_resolution)
	shader_material.set_shader_parameter("lod_dropoff_rate", lod_dropoff_rate)
	
	shader_material.set_shader_parameter("triplanar_on_texture_0", enable_triplanar_on_texture_0)
	shader_material.set_shader_parameter("triplanar_on_texture_1", enable_triplanar_on_texture_1)
	shader_material.set_shader_parameter("triplanar_on_texture_2", enable_triplanar_on_texture_2)
	shader_material.set_shader_parameter("triplanar_on_texture_3", enable_triplanar_on_texture_3)

func _create_lod_meshes():
	lod_meshes.clear()
	for i in range(highest_lod_resolution + 1):
		var quad = QuadMesh.new()
		quad.subdivide_width = _get_chunk_subdivs_for_lod(i)
		quad.subdivide_depth = _get_chunk_subdivs_for_lod(i)
		quad.material = shader_material
		quad.size = Vector2(1,1)
		quad.center_offset = Vector3(0.5,0,0.5)
		quad.orientation = PlaneMesh.FACE_Y
		lod_meshes.push_back(quad)

func _create_chunks():
	for child in chunks_container.get_children():
		chunks_container.remove_child(child)
		child.queue_free()
	chunks_container.position = get_total_size() * -ONE_HALF_XZ if centered else Vector3.ZERO
	chunks.clear()
	chunks.resize(chunk_count.x)
	for x in chunk_count.x:
		var col = []
		col.resize(chunk_count.y)
		chunks[x] = col
		for z in chunk_count.y:
			var mesh_instance = MeshInstance3D.new()
			mesh_instance.layers = visual_instance_3d_layers
			mesh_instance.mesh = lod_meshes.back()
			mesh_instance.position = Vector3(x,0,z) * terrain_xz_scale
			mesh_instance.scale = Vector3(terrain_xz_scale, 1, terrain_xz_scale)
			chunks_container.add_child(mesh_instance)
			# Extend AABB because it won't be affected when we deform the mesh in the vertex shader
			if is_equal_approx(self.rotation.x, 0) and is_equal_approx(self.rotation.y, 0) and is_equal_approx(self.rotation.z, 0):
				mesh_instance.custom_aabb = mesh_instance.get_aabb()
				mesh_instance.custom_aabb.size.y = 5000
				mesh_instance.custom_aabb.position.y -= 2500
				mesh_instance.extra_cull_margin = 0
			else:
				# If terrain is rotated can't just increase size vertically
				mesh_instance.custom_aabb = AABB()
				mesh_instance.extra_cull_margin = 2500
			chunks[x][z] = mesh_instance

func remove_collision_shape() -> void:
	if has_collision_shape():
		var child = get_node_or_null("StaticBody3D")
		remove_child(child)
		child.queue_free()

func has_collision_shape() -> bool:
	return get_node_or_null("StaticBody3D") != null

func _collision_shape_has_vert_at(x : int, z : int, splatmap_image = null) -> bool:
	# Create holes for parts of splatmap that are transparent
	if not splatmap_image:
		splatmap_image = UTILS.get_image_texture_with_fallback(splatmap_texture, Color.BLACK).get_image()
	if splatmap_image.is_compressed():
		splatmap_image.decompress()
	var splat_px_x := func(x): return int((float(x) / float(_get_num_verts_along_edge_total(collision_shape_resolution).x - 1)) * float(splatmap_image.get_width() - 1))
	var splat_px_y := func(y): return int((float(y) / float(_get_num_verts_along_edge_total(collision_shape_resolution).y - 1)) * float(splatmap_image.get_height() - 1))
	if splatmap_image.get_pixel(splat_px_x.call(x), splat_px_y.call(z)).a < 0.0001:
		# In the shader, only making it transparent if all 3 vertices of tri are transparent. Need same logic here.
		# If you look at the mesh, each point touches 6 triangles, these are the other points making up the 6
		# If any of the triangle points is not fully transparent, this point can't be either b/c of varying interpolation
		# Even though the vertex shader was sampled as fully transparent at this vert, we know transparency will be
		# ignored in fragment if it fails any of these checks:
		var l = get_terrain_pixel(splatmap_texture, splat_px_x.call(x - 1), splat_px_y.call(z + 0), Color.BLACK).a < 0.0001
		var r = get_terrain_pixel(splatmap_texture, splat_px_x.call(x + 1), splat_px_y.call(z + 0), Color.BLACK).a < 0.0001
		var t = get_terrain_pixel(splatmap_texture, splat_px_x.call(x + 0), splat_px_y.call(z + 1), Color.BLACK).a < 0.0001
		var b = get_terrain_pixel(splatmap_texture, splat_px_x.call(x + 0), splat_px_y.call(z - 1), Color.BLACK).a < 0.0001
		var br = get_terrain_pixel(splatmap_texture, splat_px_x.call(x + 1), splat_px_y.call(z - 1), Color.BLACK).a < 0.0001
		var tr = get_terrain_pixel(splatmap_texture, splat_px_x.call(x - 1), splat_px_y.call(z + 1), Color.BLACK).a < 0.0001
		if l and r and t and b and br and tr:
			return false
	return true

func get_collision_shape_data(num_verts_along_edge_total : Vector2i, height_scale_fix : float) -> PackedFloat32Array:
	#var scale_xz = (get_total_size() / (num_verts_along_edge_total - 1)).x
	var map_data := PackedFloat32Array()
	map_data.resize(num_verts_along_edge_total.x * num_verts_along_edge_total.y)
	
	# Since we must scale the collision shape uniformly, we modify the height of each point, 
	# normalizing it to the terrain_height_scale value
	var scale_y_to_normalize = terrain_height_scale / height_scale_fix
	var heightmap_image = UTILS.get_image_texture_with_fallback(heightmap_texture, Color.BLACK).get_image()
	if heightmap_image.is_compressed():
		heightmap_image.decompress()
	var splatmap_image = UTILS.get_image_texture_with_fallback(splatmap_texture, Color.BLACK).get_image()
	if splatmap_image.is_compressed():
		splatmap_image.decompress()
	# Make a copy before editing because if we don't it triggers collision shape recompute on every
	# assignment which lags the editor a lot.
	var m = -1.0
	for i in map_data.size():
		# Is this right or should be num_verts_along_edge_total + 1
		var x = i % num_verts_along_edge_total.x
		var z = floor(i / num_verts_along_edge_total.x)
		var hpixel_x := int((float(x) / float(num_verts_along_edge_total.x - 1)) * float(heightmap_image.get_width() - 1))
		var hpixel_y := int((float(z) / float(num_verts_along_edge_total.y - 1)) * float(heightmap_image.get_height() - 1))
		map_data[i] = heightmap_image.get_pixel(hpixel_x, hpixel_y).r * scale_y_to_normalize
		# Create holes for parts of splatmap that are transparent
		if not _collision_shape_has_vert_at(x, z, splatmap_image):
			map_data[i] = NAN
	return map_data

func make_heightmap_shape(data : PackedFloat32Array, data_width_depth : Vector2i) -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = data_width_depth.x
	shape.map_depth = data_width_depth.y
	shape.map_data = data
	return shape

func create_collision_shape():
	var static_body : StaticBody3D = get_node_or_null("StaticBody3D")
	if static_body == null:
		static_body = StaticBody3D.new()
		static_body.name = "StaticBody3D"
		add_child(static_body)
		if Engine.is_editor_hint():
			static_body.owner = get_tree().edited_scene_root
	var collision_shape : CollisionShape3D = static_body.get_node_or_null("CollisionShape3D")
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		static_body.add_child(collision_shape)
		if Engine.is_editor_hint():
			collision_shape.owner = get_tree().edited_scene_root
	
	collision_shape.position = Vector3.ZERO if centered else get_total_size() * ONE_HALF_XZ
	var num_verts_along_edge_total = _get_num_verts_along_edge_total(collision_shape_resolution)
	var scale_xz = (terrain_xz_scale / (_get_num_verts_along_chunk_edge(collision_shape_resolution) - 1))
	collision_shape.scale = Vector3(scale_xz, scale_xz, scale_xz)
	
	# This was causing lag on level spawn but it got fixed randomly at some point? Maybe 4.2.1 bump?
	collision_shape.shape = make_heightmap_shape(get_collision_shape_data(num_verts_along_edge_total, scale_xz), num_verts_along_edge_total)


func _update_lods():
	var cam_chunk_loc = _get_camera_location_in_chunks()
	# Update non constant shader parameters
	update_shader_params(true)
	for x in chunk_count.x:
		for z in chunk_count.y:
			var diff = max(abs(x - cam_chunk_loc.x), abs(cam_chunk_loc.y), abs(z - cam_chunk_loc.z))
			var lod : int = max(0, highest_lod_resolution - int(float(diff) * lod_dropoff_rate))
			chunks[x][z].mesh = lod_meshes[lod]

func _update_meshes():
	if not is_inside_tree():
		# Make sure an export var setter doesn't try to update the meshes before in tree
		return
	_create_lod_meshes()
	_create_chunks()
	update_shader_params()
	_update_lods()
	# Create a collision shape at runtime if there isn't already one
	if not Engine.is_editor_hint() and get_collision_body() == null and use_collision:
		if heightmap_texture is NoiseTexture2D:
			create_collision_shape.call_deferred()
		else:
			create_collision_shape()

func get_collision_body() -> StaticBody3D:
	for child in get_children():
		if child is StaticBody3D and child.get_child(0) is CollisionShape3D and child.get_child(0).shape is HeightMapShape3D:
			return child
	return null

# For a given LOD, get the triangle the given point is within. Returns Vector3 for 3 triangle verts in clockwise order
func get_tri_at_xz(global_pos : Vector3, lod : int, local_to_chunks_container := false) -> Array:
	var local_pos := chunks_container.global_transform.affine_inverse() * global_pos
	var num_quads_along_edge_total := _get_num_verts_along_edge_total(lod) - Vector2i(1, 1)
	var quad_size := get_total_size_without_height() / Vector2(num_quads_along_edge_total)
	var quad_idx := Vector2i((Vector2(local_pos.x, local_pos.z) / quad_size).floor())
	var quad_local_pos_normalized := Vector2(local_pos.x, local_pos.z) - Vector2(quad_idx) * quad_size
	var in_top_left_tri := quad_local_pos_normalized.y > quad_local_pos_normalized.x
	var verts := []
	if in_top_left_tri:
		verts = [quad_idx, quad_idx + Vector2i(1,0), quad_idx + Vector2i(0,1)]
	else: # in bottom right tri
		verts = [quad_idx + Vector2i(1,0), quad_idx + Vector2i(1,1), quad_idx + Vector2i(0,1)]
	
	var heightmap_image = UTILS.get_image_texture_with_fallback(heightmap_texture, Color.BLACK).get_image()
	var iw = heightmap_image.get_width()
	var ih = heightmap_image.get_height()
	for i in len(verts):
		var v = verts[i]
		var hpixel_x := int((float(v.x) / float(_get_num_verts_along_edge_total(lod).x - 1)) * float(heightmap_image.get_width() - 1))
		var hpixel_y := int((float(v.y) / float(_get_num_verts_along_edge_total(lod).y - 1)) * float(heightmap_image.get_height() - 1))
		hpixel_x = clamp(hpixel_x, 0, iw-1)
		hpixel_y = clamp(hpixel_y, 0, ih-1)
		var h = heightmap_image.get_pixel(hpixel_x, hpixel_y).r * terrain_height_scale
		var pos := Vector3(v.x * quad_size.x, h, v.y * quad_size.y)
		if not local_to_chunks_container:
			pos = chunks_container.global_transform * pos
		verts[i] = pos
	return verts

func get_real_local_height_at_pos(global_pos : Vector3, lod : int) -> float:
	var tri := get_tri_at_xz(global_pos, lod, true)
	var local_pos := chunks_container.global_transform.affine_inverse() * global_pos
	return UTILS.get_point_y_on_plane(Vector2(local_pos.x, local_pos.z), tri[0], tri[1], tri[2])

######################
## Built in methods ##
######################

func _notification(what):
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		update_shader_params()

func _init():
	add_child(chunks_container)

func _ready():
	if Engine.is_editor_hint():
		_editor_csg_box = CSGBox3D.new()
		_editor_csg_box.visibility_range_begin = INF
		add_child(_editor_csg_box, false, Node.INTERNAL_MODE_BACK)
		_editor_csg_box.owner = self
	set_notify_transform(true)
	_update_meshes()

func _process(delta):
	_update_lods()
	if Engine.is_editor_hint():
		if update_normal_map_every_frame_in_editor:
			update_normalmap_and_set_shader_parameter()
		if _editor_csg_box:
			_editor_csg_box.size = Vector3(chunk_count.x * terrain_xz_scale, 1, chunk_count.y * terrain_xz_scale)
