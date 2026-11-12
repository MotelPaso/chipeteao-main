class_name Telegraph
extends RefCounted
## Puerta de entrada de los avisos en el suelo: un disco plano sin sombreado
## que crece desde el centro hasta el radio completo durante la carga (lo
## lleno se lee como cuenta regresiva) y luego se desvanece. El disco es un TelegraphDisc del pool, vive en la raíz de la
## escena (sobrevive si quien lo lanzó muere a mitad del aviso) y vuelve
## solo al pool tras desvanecerse. Solo es visual: el momento del ataque y
## el daño los decide quien lo llama.


static func spawn_disc(_host: Node, center: Vector3, radius: float,
		duration: float, color: Color) -> void:
	var disc := Pools.acquire_scene(Pools.TELEGRAPH_DISC_SCENE) as TelegraphDisc
	if disc == null:
		return
	disc.show_disc(center, radius, duration, color)
