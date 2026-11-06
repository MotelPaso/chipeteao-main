class_name Health
extends Node
## Componente de vida reutilizable: va como hijo de cualquier cuerpo. Los
## cuerpos del grupo "enemies" con un Health hijo reciben daño de las armas.
## Emite died una sola vez al llegar a cero; heal_full() y revive() lo rearman.

signal damaged(amount: float, current: float)
## Se emite junto con `damaged` cuando el golpe nombra a su atacante (el daño
## por contacto de los enemigos lo hace); las espinas se enganchan aquí.
signal damaged_by(attacker: Node3D)
## Se emite en lugar de `damaged` cuando el dueño esquiva el golpe entero
## (tirada de evasión del jugador); las pasivas de ejecución al esquivar se
## enganchan aquí. `attacker` es quien nombró el golpe, o null.
signal dodged(attacker: Node3D)
## Cambios de vida que no son daño (subir max_hp, curar) para que las barras
## relean ambos valores; el daño usa la señal `damaged`.
signal hp_changed(current: float, max_hp: float)
signal died

## Vida máxima, en puntos de vida.
@export var max_hp: float = 50.0:
	set(value):
		# El setter mantiene current_hp <= max_hp: un cuerpo con la vida llena
		# sigue lleno al subirla, uno herido queda recortado, y hp_changed
		# informa ambos valores a las barras.
		var was_full := _initialized and is_equal_approx(current_hp, max_hp)
		max_hp = value
		# Al instanciar la escena este export se escribe ANTES de que _ready
		# fije current_hp: todavía no hay invariante que mantener.
		if not _initialized:
			return
		current_hp = max_hp if was_full else minf(current_hp, max_hp)
		hp_changed.emit(current_hp, max_hp)
## Muestra los números de daño flotantes sobre este cuerpo.
@export var show_damage_popups: bool = true
## Reducción plana de daño por golpe; en el jugador la escribe PlayerStats (Tomo de Piedra).
@export var armor: float = 0.0
## Texto flotante al esquivar un golpe entero (tirada de evasión del jugador).
@export var dodge_text: String = "!"


## Lo activa PowerUps durante Inmortalidad: rechaza todo golpe (antes de la
## armadura y de la evasión) y lo cuenta. El godmode del soak no lo usa: sube
## max_hp para seguir ejercitando el camino de daño real.
var invulnerable: bool = false
## Golpes rechazados por invulnerable (el soak lo lee para probar que un
## enemigo sí atacó).
var blocked_hits: int = 0
## Fracción del golpe que vuelve al atacante (PowerUps pone 1.0 durante
## Reflejo). Se evalúa ANTES del rechazo por invulnerable: inmortal y
## reflejando a la vez devuelve todo sin recibir nada.
var reflect_fraction: float = 0.0


## La armadura nunca anula un golpe: todo golpe que entra quita al menos esto,
## así un build de armadura apilada tiene que seguir esquivando.
const MIN_CHIP_DAMAGE: float = 1.0

var current_hp: float
var is_dead: bool = false
## True cuando _ready ya fijó current_hp; antes, el setter de max_hp no tiene
## invariante que cuidar.
var _initialized: bool = false


func _ready() -> void:
	current_hp = max_hp
	_initialized = true


## El Health de un cuerpo, o null si no tiene.
static func find_in(body: Node) -> Health:
	for child in body.get_children():
		if child is Health:
			return child
	return null


## Aplica un golpe y devuelve la vida que quitó de verdad: 0.0 si se rechazó
## (cuerpo muerto, cantidad no positiva, invulnerable) o se esquivó, la
## cantidad tras la armadura si entró, y en un golpe letal solo la vida que
## quedaba. `attacker` (opcional) es el cuerpo que golpea: los atacantes por
## contacto se pasan a sí mismos para que las espinas respondan por damaged_by.
func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	# Reflejo devuelve la cantidad BRUTA, antes de la armadura y del rechazo de
	# abajo: vuelve lo que se lanzó, no lo que entró. Sin atacante nombrado no
	# hay a quién devolverlo.
	if reflect_fraction > 0.0 and attacker != null:
		_reflect_to(attacker, amount * reflect_fraction)
	if invulnerable:
		blocked_hits += 1
		return 0.0
	var evade_chance := _evasion_chance()
	if evade_chance > 0.0 and randf() < evade_chance:
		if show_damage_popups:
			_spawn_popup(dodge_text, 64, false, true)
		Sfx.play(&"dodge")
		dodged.emit(attacker)
		return 0.0
	var final_amount := minf(amount, maxf(amount - armor, MIN_CHIP_DAMAGE))
	# Lo que el cuerpo aún puede perder: un golpe letal cuenta solo la vida que
	# quitó, nunca la tirada entera.
	var applied := minf(final_amount, current_hp)
	current_hp = maxf(current_hp - final_amount, 0.0)
	if show_damage_popups:
		_spawn_damage_popup(final_amount, is_crit)
	damaged.emit(final_amount, current_hp)
	# Antes de la comprobación de muerte, así hasta el golpe letal se devuelve.
	if attacker != null:
		damaged_by.emit(attacker)
	if current_hp <= 0.0:
		is_dead = true
		died.emit()
	return applied


## Pago voluntario de vida (Santuario de la codicia): ignora la armadura, no
## muestra número y nunca mata, porque siempre deja al menos min_remaining.
## Devuelve la vida pagada.
func pay(amount: float, min_remaining: float = 1.0) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var paid := minf(amount, maxf(current_hp - min_remaining, 0.0))
	current_hp -= paid
	hp_changed.emit(current_hp, max_hp)
	return paid


## Curación parcial (robo de vida y similares): recortada a max_hp; no hace
## nada con el cuerpo muerto.
func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_hp = minf(current_hp + amount, max_hp)
	hp_changed.emit(current_hp, max_hp)


## Cura todo y rearma died.
func heal_full() -> void:
	current_hp = max_hp
	is_dead = false
	hp_changed.emit(current_hp, max_hp)


## Reanimación en co-op: rearma un Health muerto con `fraction` de max_hp
## (died puede volver a emitirse). No hace nada si el cuerpo no está muerto.
func revive(fraction: float) -> void:
	if not is_dead:
		return
	is_dead = false
	current_hp = clampf(max_hp * fraction, 1.0, max_hp)
	hp_changed.emit(current_hp, max_hp)


## Devuelve `amount` al Health del atacante. Este cuerpo va como atacante,
## así espinas y ejecuciones ven un golpe normal; no puede hacer bucle porque
## solo un raider tiene reflect_fraction.
func _reflect_to(attacker: Node3D, amount: float) -> void:
	if not is_instance_valid(attacker) or attacker == get_parent():
		return
	var target := Health.find_in(attacker)
	if target == null or target == self or target.is_dead:
		return
	target.take_damage(amount, false, get_parent() as Node3D)


## Probabilidad (0-1) de esquivar el golpe entero. Solo el jugador esquiva,
## leída de su PlayerStats (que ya la topa); los enemigos nunca tiran.
func _evasion_chance() -> float:
	var body := get_parent()
	if body == null or not body.is_in_group("player"):
		return 0.0
	var stats := PlayerStats.find_in(body)
	return stats.evasion if stats != null else 0.0


func _spawn_damage_popup(amount: float, is_crit: bool) -> void:
	_spawn_popup(str(roundi(amount)), 88 if is_crit else 64, is_crit)


func _spawn_popup(popup_text: String, popup_font_size: int, is_crit: bool, is_dodge:bool = false) -> void:
	var body := get_parent() as Node3D
	if body == null:
		return
	# Label3D del pool; Pools lo cuelga de la arena, así sobrevive a la muerte
	# del cuerpo.
	var popup := Pools.acquire_scene(Pools.DAMAGE_POPUP_SCENE) as DamagePopup
	if popup == null:
		return
	popup.show_popup(popup_text, popup_font_size, is_crit, body.global_position
			+ Vector3(randf_range(-0.3, 0.3), 2.0, randf_range(-0.3, 0.3)), is_dodge)
