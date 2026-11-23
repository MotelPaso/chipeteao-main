class_name EnemySkyDrop
extends RefCounted
## Entrada cayendo del cielo (lluvia de enemigos). El cuerpo ya está en el
## suelo, apagado (sin proceso ni colisión) mientras su dibujo baja desde
## `height`; al aterrizar el dibujo vuelve a su sitio y el cuerpo despierta.
## Los valores los pone el enemigo (EnemyBase, grupo «Caída del cielo»).


static func play(enemy: Node3D, visual: Node3D, height: float, seconds: float) -> void:
	if visual == null or height <= 0.0 or seconds <= 0.0:
		return
	var rest := visual.position
	visual.position = rest + Vector3.UP * height
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	# Tween del árbol, no del nodo: un tween del enemigo apagado no corre.
	var tween := enemy.get_tree().create_tween()
	tween.tween_property(visual, "position", rest, seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Referencia débil: el enemigo puede liberarse mientras cae, y una lambda
	# que lo captura directo falla al llamarse.
	var enemy_ref: WeakRef = weakref(enemy)
	tween.tween_callback(func() -> void:
		var body := enemy_ref.get_ref() as Node
		if body != null:
			body.process_mode = Node.PROCESS_MODE_INHERIT)
