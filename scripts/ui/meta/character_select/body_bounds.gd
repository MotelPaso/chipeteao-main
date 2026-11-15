class_name BodyBounds
extends RefCounted
## Mide el cuerpo 3D que un SealRig tiene armado, para que una cámara lo
## encuadre mida lo que mida su modelo. Lo comparten el retrato giratorio del
## detalle (CharacterPortrait) y las caras de las cartas (PortraitStudio).
## Es estático y nunca va en una escena.


## Caja que envuelve el cuerpo de `rig`, en el espacio de `pivot`. Una malla
## rígida aporta su caja; una malla con esqueleto aporta las articulaciones de
## su pose actual (su caja propia está en la pose y la escala de exportación,
## no donde se dibuja), con `skin_padding` de holgura (fracción de su alto)
## por el grosor del cuerpo. Un cuerpo anterior que sigue en el árbol hasta el
## final del frame (SealRig lo libera diferido) no se cuenta. Sin mallas
## devuelve una caja vacía.
static func of(rig: Node3D, pivot: Node3D, skin_padding: float) -> AABB:
	var boxes: Array[AABB] = []
	var skeletons: Array[Skeleton3D] = []
	var to_pivot := pivot.global_transform.affine_inverse()
	for node: Node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree() or _is_leaving(mesh, rig):
			continue
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if mesh.skin == null or skeleton == null:
			boxes.append((to_pivot * mesh.global_transform) * mesh.get_aabb())
		elif not skeletons.has(skeleton):
			skeletons.append(skeleton)
	for skeleton: Skeleton3D in skeletons:
		var joints := _joint_bounds(skeleton, to_pivot * skeleton.global_transform)
		boxes.append(joints.grow(joints.size.y * skin_padding))
	if boxes.is_empty():
		return AABB()
	var bounds := boxes[0]
	for box: AABB in boxes:
		bounds = bounds.merge(box)
	return bounds


## Caja de las articulaciones del esqueleto en su pose actual.
static func _joint_bounds(skeleton: Skeleton3D, to_pivot: Transform3D) -> AABB:
	var bounds := AABB()
	for bone in skeleton.get_bone_count():
		var joint := to_pivot * skeleton.get_bone_global_pose(bone).origin
		bounds = AABB(joint, Vector3.ZERO) if bone == 0 else bounds.expand(joint)
	return bounds


static func _is_leaving(node: Node, rig: Node) -> bool:
	var current := node
	while current != null and current != rig:
		if current.is_queued_for_deletion():
			return true
		current = current.get_parent()
	return false
