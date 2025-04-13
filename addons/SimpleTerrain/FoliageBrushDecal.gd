@tool
class_name FoliageBrushDecal
extends Decal

const UTILS = preload("res://addons/SimpleTerrain/SimpleTerrainUtils.gd")

var follow_mouse := true
var painting := false
var undo_redo : EditorUndoRedoManager
var last_paint_position : Vector3 = Vector3.ZERO
var brush_mode : UTILS.FoliageBrushMode = UTILS.FoliageBrushMode.ADD

# New variables for grid-based painting
var current_seed: int = 0
var stroke_start_pos_xz: Vector2 = Vector2.ZERO
var already_painted_dict: Dictionary = {}

# State tracking for undo/redo
var _current_pre_removal_transforms: Array[Transform3D] = []
var _current_post_removal_transforms: Array[Transform3D] = []
var _removal_occurred := false
var _stroke_started := false # Track if we've started a new stroke

# Renamed from opacity
@export_range(0.01, 1.0) var density := 1 :
	set(value):
		if density != value:
			density = value
			_update_textures()
@export_range(1,4096) var brush_size : int = 64 :
	set(value):
		if brush_size != value:
			brush_size = value
			_update_textures()
# Renamed from hardness
@export_range(0.0, 1.0) var randomness := 0.25 :
	set(value):
		if randomness != value:
			randomness = value
			_update_textures()

# Foliage painting specific settings
@export var random_rotation := true
@export var random_scale := true
@export_range(0.5, 1.5) var random_scale_min := 0.8
@export_range(0.5, 2.0) var random_scale_max := 1.2

var paint_texture := GradientTexture2D.new()
const PAINT_RATE_MS = 1000/20  # Slower rate than terrain painting
var _last_paint_time = Time.get_ticks_msec()
var _initial_instance_count := 0
var _added_transforms: Array[Transform3D] = []
var _was_painting_last_frame := false # Track painting state
var _created_multimesh_this_stroke := false # Track if MM was created by this action

# Get the terrain and foliage nodes
func get_terrain_node() -> SimpleTerrain:
	var current = self
	while current:
		current = current.get_parent()
		if current is SimpleTerrain:
			return current
		if current and current.get_parent():
			for node in current.get_parent().get_children():
				if node is SimpleTerrain:
					return node
	return null

func get_foliage_node() -> SimpleTerrainFoliage:
	var current = self
	while current:
		current = current.get_parent()
		if current is SimpleTerrainFoliage:
			return current
	return null

static func update_gradient_texture(gradient_tex : GradientTexture2D, size : int, density : float, randomness : float, marker : bool):
	gradient_tex.width = size
	gradient_tex.height = size
	gradient_tex.fill_from = Vector2(0.5, 0.5)
	gradient_tex.fill_to = Vector2(1.0, 0.5)
	gradient_tex.fill = GradientTexture2D.FILL_RADIAL
	if gradient_tex.gradient == null:
		gradient_tex.gradient = Gradient.new()
	gradient_tex.gradient.interpolation_color_space = Gradient.GRADIENT_COLOR_SPACE_LINEAR_SRGB
	gradient_tex.gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	# Clear existing points except the last one before adding new ones
	while gradient_tex.gradient.get_point_count() > 1:
		gradient_tex.gradient.remove_point(0)
	
	if marker:
		# Visual effect: randomness controls blur/spread
		var diff = lerp(0.1, 0.4, randomness) # Higher randomness -> larger diff -> more blur
		# --- Use fixed alpha values for consistent marker appearance --- 
		gradient_tex.gradient.set_color(0, Color(1, 1, 1, 0.05)) # Fixed low alpha for inner part
		gradient_tex.gradient.set_offset(0, 0.95 - diff)
		gradient_tex.gradient.add_point(0.95 - diff/2, Color(1, 1, 1, 0.5)) # Fixed higher alpha for edge
		gradient_tex.gradient.add_point(1.0, Color.TRANSPARENT)
	else:
		# For the actual paint texture (if needed), use density and randomness
		gradient_tex.gradient.set_color(0, Color(1, 1, 1, density))
		gradient_tex.gradient.set_offset(0, 0.0)
		gradient_tex.gradient.add_point((1.0 - randomness) * 0.9999, Color(1, 1, 1, density))
		gradient_tex.gradient.add_point(1.0, Color.TRANSPARENT)

func _scale_decal_to_texture_size():
	var terrain = get_terrain_node()
	if not terrain: return
	
	# Scale decal visually based on brush_size relative to terrain
	# Assume terrain dimensions are available (replace with actual properties if needed)
	var terrain_size = terrain.get_total_size_without_height() # Example getter
	if terrain_size.x <= 0 or terrain_size.y <= 0:
		print("Warning: Invalid terrain size for decal scaling.")
		return 
		
	# Calculate decal size based on brush_size proportion to terrain
	# This assumes brush_size corresponds to pixels on a default texture size (e.g., 1024)
	var default_texture_size = 1024.0 
	var relative_size = float(brush_size) / default_texture_size
	var diameter = relative_size * terrain_size.x # Use x dimension for consistency
	
	self.size = Vector3(diameter, 50, diameter) # Use fixed height
	#print("Scaled decal based on brush_size: ", brush_size, " -> size: ", self.size)

func _update_textures():
	if texture_albedo == null:
		texture_albedo = GradientTexture2D.new()
	update_gradient_texture(texture_albedo, 256, density, randomness, true)
	update_gradient_texture(paint_texture, brush_size, density, randomness, false)
	_scale_decal_to_texture_size() # Restore call: update decal when brush_size changes

func _raycast_and_snap_to_terrain(camera: Camera3D, screen_pos: Vector2) -> void:
	if not follow_mouse:
		self.visible = false
		return
		
	# Need to do an extra conversion in case the editor viewport is in half-resolution mode
	var viewport := camera.get_viewport()
	var viewport_container : Control = viewport.get_parent()
	var screen_pos_adjusted = screen_pos * Vector2(viewport.size) / viewport_container.size
	
	var origin = camera.project_ray_origin(screen_pos_adjusted)
	var dir = camera.project_ray_normal(screen_pos_adjusted)
	
	# Get the terrain node
	var terrain = get_terrain_node()
	if terrain:
		var hit_pos = null
		var physics_hit = false
		
		# --- Try physics raycast first if collision body exists ---
		var collision_body = terrain.get_collision_body() # Assuming this function exists
		if collision_body and collision_body is CollisionObject3D:
			#print("Collision body found", collision_body) # Keep for debugging if needed
			var space_state = get_world_3d().direct_space_state
			var exclude : Array[RID] = []
			const MAX_ITERATIONS = 10

			for i in range(MAX_ITERATIONS):
				var query_params = PhysicsRayQueryParameters3D.create(origin, origin + dir * camera.far * 1.2, collision_body.collision_mask)
				query_params.collide_with_bodies = true
				query_params.collide_with_areas = false
				query_params.exclude = exclude # Apply exclusion list
				
				var physics_result = space_state.intersect_ray(query_params)
				
				if not physics_result:
					# Ray hit nothing further along the path
					#print("Physics raycast stopped: Hit nothing further.")
					break 
				
				if physics_result.collider == collision_body:
					# Hit the terrain!
					#print("Physics hit terrain on iteration ", i, physics_result)
					hit_pos = physics_result.position
					physics_hit = true
					break # Found the terrain, exit loop
				else:
					# Hit something else, add it to exclude list and try again
					#print("Physics hit other object on iteration ", i, ": ", physics_result.collider, " Adding RID: ", physics_result.rid)
					exclude.append(physics_result.rid)
					# Continue to next iteration

		# --- End Physics Raycast ---

		# --- Fallback to pixel raycast if physics failed or no body ---
		if not physics_hit:
			#print("Physics raycast failed to hit terrain, falling back to pixel raycast.") # Keep for debugging
			var result = terrain.raycast_terrain_by_px(origin, dir * camera.far * 1.2, false)
			if result and result.size() > 0 and result[0] != null: # Ensure result exists and is valid
				hit_pos = result[0]
		# --- End Fallback Raycast ---

		if hit_pos != null:
			global_position = hit_pos
			self.visible = true
		else:
			self.visible = false
	else:
		self.visible = false

func _get_pos_on_texture(texture : Texture2D, world_pos: Vector3) -> Vector2i:
	if not is_inside_tree() or not texture: return Vector2i(0,0)
	var terrain = get_terrain_node()
	if not terrain: return Vector2i(0,0)
	var norm_pos := terrain.get_global_pos_normalized_to_terrain(world_pos)
	var to_px := Vector2(norm_pos.x, norm_pos.z) * Vector2(texture.get_image().get_size())
	return Vector2i(round(to_px.x),round(to_px.y))

func _before_paint_foliage():
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
		
	var foliage = get_foliage_node()
	# Check if foliage node exists at all
	if not foliage:
		printerr("FoliageBrushDecal: Cannot find SimpleTerrainFoliage parent node.")
		return
		
	# Check if foliage mesh is assigned (needed for creation)
	if not foliage.foliage_mesh:
		printerr("FoliageBrushDecal: Foliage node has no foliage_mesh assigned. Cannot paint.")
		return # Cannot paint or create multimesh without a mesh
	
	# Reset stroke creation flag
	_created_multimesh_this_stroke = false
	var new_multimesh = null # Variable to hold newly created multimesh for undo/redo
	
	# --- Create MultiMesh if it doesn't exist --- 
	if not foliage.multimesh:
		print("FoliageBrushDecal: Foliage node multimesh is null. Creating new one.")
		new_multimesh = MultiMesh.new()
		new_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		new_multimesh.instance_count = 100 # Sensible default initial size
		new_multimesh.visible_instance_count = 0
		new_multimesh.mesh = foliage.foliage_mesh # Assign the mesh
		
		# IMPORTANT: Directly assign the resource to the node property
		foliage.multimesh = new_multimesh 
		_created_multimesh_this_stroke = true
		_initial_instance_count = 0 # If we just created it, initial count is 0
	# --- End MultiMesh Creation ---
	else:
		# If multimesh already exists, get its current visible count
		_initial_instance_count = foliage.multimesh.visible_instance_count

	# Initialize stroke variables
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	current_seed = rng.randi()
	stroke_start_pos_xz = Vector2(global_position.x, global_position.z)
	already_painted_dict = {}
	_added_transforms.clear()
	
	# For REMOVE mode, capture initial state only at stroke start
	if brush_mode == UTILS.FoliageBrushMode.REMOVE and not _stroke_started:
		_stroke_started = true
		_removal_occurred = false
		if foliage.multimesh:
			_current_pre_removal_transforms.clear()
			for i in range(foliage.multimesh.visible_instance_count):
				_current_pre_removal_transforms.append(foliage.multimesh.get_instance_transform(i))

# --- Helper: Calculate Grid Step based on brush radius and desired density --- #
func _get_grid_step(radius: float, desired_points: int) -> float:
	if radius <= 0.0 or density <= 0.0:
		return 10.0 # Return default step if inputs invalid
	
	var area = PI * radius * radius
	var grid_step_sq = area / desired_points
	return maxf(0.1, sqrt(grid_step_sq)) # Ensure step is not zero

func _paint_foliage():
	if not Engine.is_editor_hint() or not is_inside_tree(): 
		return
		
	var foliage = get_foliage_node()
	if not foliage or not foliage.foliage_mesh:
		print("Paint Foliage: No foliage node or mesh")
		return
	
	var terrain = get_terrain_node()
	if not terrain or not terrain.heightmap_texture:
		print("Paint Foliage: No terrain node or heightmap")
		return
	
	# Define sampling parameters
	var current_pos_xz = Vector2(global_position.x, global_position.z)
	var radius = self.size.x * 0.5 
	if radius <= 0: return # Avoid issues if decal size is invalid
	
	# --- Handle different brush modes ---
	if brush_mode == UTILS.FoliageBrushMode.ADD:
		_add_foliage_in_radius(foliage, terrain, current_pos_xz, radius)
	elif brush_mode == UTILS.FoliageBrushMode.REMOVE:
		_remove_foliage_in_radius(foliage, current_pos_xz, radius)
	elif brush_mode == UTILS.FoliageBrushMode.ADD_STACKED:
		_add_stacked_foliage_in_radius(foliage, terrain, current_pos_xz, radius)
	# else: # Handle other modes like Smooth, Flatten later if needed
		# pass 

# --- Renamed and refactored from the original _paint_foliage ADD logic ---
func _add_foliage_in_radius(foliage: SimpleTerrainFoliage, terrain: SimpleTerrain, current_pos_xz: Vector2, radius: float):
	# --- Calculate effective radius from decal size --- 
	# radius is already passed in
	# --- End radius calculation ---
	var area_start_pos = current_pos_xz - Vector2(radius, radius)
	var area_size = Vector2(radius, radius) * 2.0

	# Calculate grid step based on density and calculated radius
	var grid_step = _get_grid_step(radius, density) # Density likely needs adjustment for desired points *within* the circle

	# Sample points in the area around the brush
	var sampled_points = _sample_field_in_area(
		area_start_pos, 
		area_size, 
		randomness, # Use the exported randomness directly
		grid_step, 
		current_seed, 
		stroke_start_pos_xz # Use the stroke start for grid alignment
	)
	
	# --- Create list to store transforms for this frame's bulk add --- 
	var new_transforms_this_frame: Array[Transform3D] = []
	
	# Process sampled points
	for point_xz in sampled_points:
		# Determine grid cell for uniqueness check
		var grid_key = Vector2i(floor(point_xz.x / grid_step), floor(point_xz.y / grid_step))
		
		# Check if this grid cell has already been painted in this stroke
		if already_painted_dict.has(grid_key):
			continue
			
		# Check if the point is within the circular brush radius 
		if current_pos_xz.distance_to(point_xz) > radius: # Use calculated radius
			continue

		# Calculate world position and get height
		var instance_position = Vector3(point_xz.x, 0, point_xz.y)
		# Use terrain reference passed into the function
		#var px = _get_pos_on_texture(terrain.heightmap_texture, instance_position)
		#var height = terrain.get_terrain_pixel(terrain.heightmap_texture, px.x, px.y).r * terrain.terrain_height_scale
		# Get height and add the offset
		var terrain_local_y = terrain.get_real_local_height_at_pos(foliage.global_transform * instance_position, terrain.highest_lod_resolution)
		instance_position.y = terrain_local_y + foliage.height_offset
		
		# --- Create Transform (copied from add_instance_at_position logic) --- 
		var transform = Transform3D.IDENTITY
		if random_rotation:
			transform = transform.rotated(Vector3.UP, randf() * TAU)
		
		# Apply scale (Using foliage node's instance_scale)
		var instance_scale = foliage.instance_scale
		if random_scale:
			instance_scale *= randf_range(random_scale_min, random_scale_max)
		transform = transform.scaled(Vector3(instance_scale, instance_scale, instance_scale))

		# Apply translation (in foliage node's local space)
		transform.origin = foliage.global_transform.affine_inverse() * instance_position
		# --- End Transform Creation --- 
		
		# Add the calculated transform to the list for bulk addition
		new_transforms_this_frame.append(transform)
		
		# Mark this grid cell as painted for this stroke (still needed)
		already_painted_dict[grid_key] = true

	# --- Perform bulk addition AFTER processing all points --- 
	if not new_transforms_this_frame.is_empty():
		foliage.add_instances_bulk(new_transforms_this_frame)
		# Append the newly added transforms to the total list for the stroke (for undo/redo)
		_added_transforms.append_array(new_transforms_this_frame)

# --- New function for stacked foliage addition ---
func _add_stacked_foliage_in_radius(foliage: SimpleTerrainFoliage, terrain: SimpleTerrain, current_pos_xz: Vector2, radius: float):
	# radius is already passed in
	var area_start_pos = current_pos_xz - Vector2(radius, radius)
	var area_size = Vector2(radius, radius) * 2.0

	# Calculate grid step based on density and calculated radius
	var grid_step = _get_grid_step(radius, density) # Density likely needs adjustment for desired points *within* the circle

	# Sample points in the area around the brush
	# Use current_pos_xz for grid_center_pos to allow stacking
	var sampled_points = _sample_field_in_area(
		area_start_pos,
		area_size,
		randomness,
		grid_step,
		current_seed,
		current_pos_xz # Use current position for grid alignment
	)

	var new_transforms_this_frame: Array[Transform3D] = []

	# Process sampled points
	for point_xz in sampled_points:
		# DO NOT check already_painted_dict - this allows stacking

		# Check if the point is within the circular brush radius
		if current_pos_xz.distance_to(point_xz) > radius:
			continue

		# Calculate world position and get height
		var instance_position = Vector3(point_xz.x, 0, point_xz.y)
		# Use get_real_local_height_at_pos for consistency and add offset
		var terrain_local_y = terrain.get_real_local_height_at_pos(foliage.global_transform * instance_position, terrain.highest_lod_resolution)
		instance_position.y = terrain_local_y + foliage.height_offset

		var transform = Transform3D.IDENTITY
		if random_rotation:
			transform = transform.rotated(Vector3.UP, randf() * TAU)

		var instance_scale = foliage.instance_scale
		if random_scale:
			instance_scale *= randf_range(random_scale_min, random_scale_max)
		transform = transform.scaled(Vector3(instance_scale, instance_scale, instance_scale))

		transform.origin = foliage.global_transform.affine_inverse() * instance_position

		new_transforms_this_frame.append(transform)

	# Perform bulk addition AFTER processing all points
	if not new_transforms_this_frame.is_empty():
		foliage.add_instances_bulk(new_transforms_this_frame)
		# Append the newly added transforms to the total list for the stroke (for undo/redo)
		_added_transforms.append_array(new_transforms_this_frame)

# --- New function to handle foliage removal ---
func _remove_foliage_in_radius(foliage: SimpleTerrainFoliage, center_xz: Vector2, radius: float):
	if not foliage or not foliage.multimesh:
		return # Nothing to remove from

	var multimesh = foliage.multimesh
	var current_visible_count = multimesh.visible_instance_count
	if current_visible_count == 0:
		return # Nothing to remove

	var kept_transforms: Array[Transform3D] = []
	var foliage_global_xform = foliage.global_transform
	var radius_sq = radius * radius # Use squared distance for efficiency

	for i in range(current_visible_count):
		var instance_transform: Transform3D = multimesh.get_instance_transform(i)
		# Instance transform origin is in foliage node's local space. Convert to world.
		var world_pos: Vector3 = foliage_global_xform * instance_transform.origin
		var instance_pos_xz = Vector2(world_pos.x, world_pos.z)
		
		# Check distance squared against radius squared
		if center_xz.distance_squared_to(instance_pos_xz) > radius_sq:
			# Keep this instance
			kept_transforms.append(instance_transform)

	# Update MultiMesh only if instances were actually removed
	if kept_transforms.size() < current_visible_count:
		var new_count = kept_transforms.size()
		
		# Make sure the buffer size is large enough
		if multimesh.instance_count < new_count:
			printerr("Warning: MultiMesh instance_count might be too small after removal.")
			new_count = min(new_count, multimesh.instance_count)
			kept_transforms.resize(new_count)

		# Store the current state for redo
		_current_post_removal_transforms = kept_transforms.duplicate()
		
		# Apply the changes
		multimesh.visible_instance_count = new_count
		for i in range(new_count):
			multimesh.set_instance_transform(i, kept_transforms[i])
			
		_removal_occurred = true

# Helper function to apply transforms to the multimesh
func _apply_transforms_to_multimesh(foliage: SimpleTerrainFoliage, transforms: Array[Transform3D]):
	if not foliage or not foliage.multimesh:
		return
		
	var multimesh = foliage.multimesh
	var new_count = transforms.size()
	
	# Ensure multimesh can hold all transforms
	if multimesh.instance_count < new_count:
		var expanded_count = max(new_count, multimesh.instance_count * 2)
		multimesh.instance_count = expanded_count
	
	# Apply all transforms
	multimesh.visible_instance_count = new_count
	for i in range(new_count):
		multimesh.set_instance_transform(i, transforms[i])

# Helper function for the redo operation of ADD mode
func _redo_paint_foliage(foliage_node: SimpleTerrainFoliage, transforms_to_add: Array[Transform3D]):
	if not foliage_node:
		print("Redo failed: Foliage node is null")
		return
	
	if transforms_to_add.is_empty():
		print("Redo: No transforms to add")
		return
		
	# Use the bulk add function for redo as well
	print("Redo: Bulk adding ", transforms_to_add.size(), " transforms")
	foliage_node.add_instances_bulk(transforms_to_add)

# Helper functions for REMOVE mode undo/redo
func _undo_remove_foliage(foliage: SimpleTerrainFoliage, pre_transforms: Array):
	_apply_transforms_to_multimesh(foliage, pre_transforms)

func _redo_remove_foliage(foliage: SimpleTerrainFoliage, post_transforms: Array):
	_apply_transforms_to_multimesh(foliage, post_transforms)

func _after_paint_foliage():
	if not Engine.is_editor_hint() or not is_inside_tree(): 
		return
		
	var foliage = get_foliage_node()
	if not foliage:
		_added_transforms.clear()
		_created_multimesh_this_stroke = false
		_removal_occurred = false
		_stroke_started = false
		return
		
	# Handle undo/redo registration based on brush mode
	if brush_mode == UTILS.FoliageBrushMode.ADD or brush_mode == UTILS.FoliageBrushMode.ADD_STACKED:
		# Skip if nothing was added AND we didn't create the multimesh
		if _added_transforms.size() == 0 and not _created_multimesh_this_stroke:
			return

		# Skip undo registration if undo_redo is not set
		if not undo_redo:
			print("Warning: undo_redo is null, cannot create undo action")
			_added_transforms.clear()
			_created_multimesh_this_stroke = false
			return

		var transforms_for_action = _added_transforms.duplicate()
		var was_created_for_action = _created_multimesh_this_stroke
		var multimesh_resource_for_action = foliage.multimesh

		undo_redo.create_action("Paint foliage")

		if was_created_for_action:
			undo_redo.add_do_property(foliage, "multimesh", multimesh_resource_for_action)
			undo_redo.add_undo_property(foliage, "multimesh", null)

		if transforms_for_action.size() > 0:
			undo_redo.add_do_method(self, "_redo_paint_foliage", foliage, transforms_for_action)
			undo_redo.add_undo_method(foliage, "set_visible_instance_count", _initial_instance_count)

		undo_redo.commit_action(false)
		
		# Reset tracking variables for ADD mode
		_added_transforms.clear()
		_created_multimesh_this_stroke = false
		
	elif brush_mode == UTILS.FoliageBrushMode.REMOVE and _removal_occurred:
		# Skip undo registration if undo_redo is not set
		if not undo_redo:
			print("Warning: undo_redo is null, cannot create undo action for removal")
			_removal_occurred = false
			_stroke_started = false
			return

		# Make copies of the current transforms for this undo action
		var pre_transforms = _current_pre_removal_transforms.duplicate()
		var post_transforms = _current_post_removal_transforms.duplicate()

		undo_redo.create_action("Remove foliage")
		
		# Register the undo/redo methods with the transform arrays
		undo_redo.add_do_method(self, "_redo_remove_foliage", foliage, post_transforms)
		undo_redo.add_undo_method(self, "_undo_remove_foliage", foliage, pre_transforms)
		
		undo_redo.commit_action(false)
		
		# Reset removal tracking
		_removal_occurred = false
		_stroke_started = false
		_current_pre_removal_transforms.clear()
		_current_post_removal_transforms.clear()

func _process(delta):
	if not Engine.is_editor_hint():
		return
		
	# Handle painting logic based on state changes
	if painting:
		# If we just started painting this frame
		if not _was_painting_last_frame:
			_before_paint_foliage() # Setup for the new stroke
			_was_painting_last_frame = true
		
		# Continue painting/removing if enough time has passed
		if Time.get_ticks_msec() - _last_paint_time > PAINT_RATE_MS:
			_paint_foliage() # Perform add or remove based on mode
			_last_paint_time = Time.get_ticks_msec()
	else:
		# If we just stopped painting this frame
		if _was_painting_last_frame:
			# Finalize the stroke and create undo action
			_after_paint_foliage()
		_was_painting_last_frame = false

func _enter_tree():
	if not Engine.is_editor_hint(): return
	_update_textures()

func _ready():
	if not Engine.is_editor_hint():
		queue_free()
		return
	self.visible = false  # Start hidden

# Uses a grid with random offsets aligned relative to grid_center_pos
func _sample_field_in_area(start_pos: Vector2, area_size: Vector2, randomness: float, grid_step: float, seed: int, grid_center_pos: Vector2) -> Array[Vector2]:
	var results: Array[Vector2] = []
	var end_pos = start_pos + area_size

	# Determine grid boundaries covering the specified area, considering max random offset
	# Note: JS used randomness * gridStep, which is half the range. 
	# randf_range gives full range, so searchExpansion needs only half gridStep * randomness.
	var search_expansion = grid_step * randomness # Max potential offset distance in one direction
	var min_check_pos = start_pos - Vector2(search_expansion, search_expansion)
	var max_check_pos = end_pos + Vector2(search_expansion, search_expansion)

	# Calculate grid indices needed to cover the check area
	var min_grid_x_index = floori(min_check_pos.x / grid_step)
	var max_grid_x_index = ceili(max_check_pos.x / grid_step)
	var min_grid_y_index = floori(min_check_pos.y / grid_step)
	var max_grid_y_index = ceili(max_check_pos.y / grid_step)

	# Index of the cell containing grid_center_pos (for relative calculation)
	var start_grid_i = floori(grid_center_pos.x / grid_step)
	var start_grid_j = floori(grid_center_pos.y / grid_step)
	# Offset of grid_center_pos within its cell (for alignment)
	var align_offset_x = grid_center_pos.x - start_grid_i * grid_step
	var align_offset_y = grid_center_pos.y - start_grid_j * grid_step

	var rng = RandomNumberGenerator.new()

	for i in range(min_grid_x_index, max_grid_x_index + 1):
		for j in range(min_grid_y_index, max_grid_y_index + 1):
			var relative_i = i - start_grid_i
			var relative_j = j - start_grid_j
			# Calculate cell seed using XOR and prime multiplication (ensure 32-bit ops)
			var cell_seed = int(seed ^ (relative_i * 16777619) ^ (relative_j * 37)) 
			# Use the cell-specific seed for the RNG
			rng.seed = cell_seed

			var base_x = i * grid_step + align_offset_x
			var base_y = j * grid_step + align_offset_y

			# Generate random offset within [-grid_step * randomness, grid_step * randomness]
			var offset_x = rng.randf_range(-1.0, 1.0) * grid_step * randomness
			var offset_y = rng.randf_range(-1.0, 1.0) * grid_step * randomness

			var final_pos = Vector2(base_x + offset_x, base_y + offset_y)

			# Only add points actually within the specified rendering bounds [start_pos, end_pos)
			if final_pos.x >= start_pos.x and final_pos.x < end_pos.x and \
				final_pos.y >= start_pos.y and final_pos.y < end_pos.y:
				results.append(final_pos)

	return results
