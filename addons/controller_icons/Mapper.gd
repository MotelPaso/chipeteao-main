func _convert_joypad_path(path: String, device: int, fallback: ControllerSettings.Devices, force_controller_icon_style = ControllerSettings.Devices.NONE) -> String:
	match _get_joypad_type(device, fallback, force_controller_icon_style):
		ControllerSettings.Devices.PS4:
			return _convert_joypad_to_ps4(path)
		ControllerSettings.Devices.PS5:
			return _convert_joypad_to_ps5(path)
		ControllerSettings.Devices.SWITCH:
			return _convert_joypad_to_switch(path)
		ControllerSettings.Devices.XBOX360:
			return _convert_joypad_to_xbox360(path)
		ControllerSettings.Devices.XBOXONE:
			return _convert_joypad_to_xboxone(path)
		_:
			return ""

## Only five icon sets ship with the game, so similar pads share one:
## a PS3 pad shows the PS4 art (same symbols), Joy-Cons show the
## Switch art and any newer Xbox pad the Xbox One art. Anything else (Steam,
## Stadia, generic pads...) falls back to settings.joypad_fallback.
func _get_joypad_type(device, fallback, force_controller_icon_style):
	if force_controller_icon_style != ControllerSettings.Devices.NONE:
		return force_controller_icon_style
	var available = Input.get_connected_joypads()
	if available.is_empty():
		return fallback
	# If the requested joypad is not on the connected joypad list, try using the last known connected joypad
	if not device in available:
		device = ControllerIcons._last_controller
	# If that fails too, then use whatever joypad we have connected right now
	if not device in available:
		device = available.front()

	var controller_name = Input.get_joy_name(device).to_lower()
	if "ps3 controller" in controller_name or \
		"ps4 controller" in controller_name or \
		"dualshock" in controller_name:
		return ControllerSettings.Devices.PS4
	elif "ps5 controller" in controller_name or \
		"dualsense" in controller_name:
		return ControllerSettings.Devices.PS5
	elif "switch controller" in controller_name or \
		"switch pro controller" in controller_name or \
		"joy-con" in controller_name:
		return ControllerSettings.Devices.SWITCH
	elif "xbox 360 controller" in controller_name:
		return ControllerSettings.Devices.XBOX360
	elif "xbox one" in controller_name or \
		"x-box one" in controller_name or \
		"xbox wireless controller" in controller_name or \
		"xbox series" in controller_name:
		return ControllerSettings.Devices.XBOXONE
	else:
		return fallback

func _convert_joypad_to_playstation(path: String):
	match path.substr(path.find("/") + 1):
		"a":
			return path.replace("/a", "/cross")
		"b":
			return path.replace("/b", "/circle")
		"x":
			return path.replace("/x", "/square")
		"y":
			return path.replace("/y", "/triangle")
		"lb":
			return path.replace("/lb", "/l1")
		"rb":
			return path.replace("/rb", "/r1")
		"lt":
			return path.replace("/lt", "/l2")
		"rt":
			return path.replace("/rt", "/r2")
		_:
			return path

func _convert_joypad_to_ps4(path: String):
	path = _convert_joypad_to_playstation(path.replace("joypad", "ps4"))
	match path.substr(path.find("/") + 1):
		"select":
			return path.replace("/select", "/share")
		"start":
			return path.replace("/start", "/options")
		"share":
			return path.replace("/share", "/")
		_:
			return path

func _convert_joypad_to_ps5(path: String):
	path = _convert_joypad_to_playstation(path.replace("joypad", "ps5"))
	match path.substr(path.find("/") + 1):
		"select":
			return path.replace("/select", "/share")
		"start":
			return path.replace("/start", "/options")
		"home":
			return path.replace("/home", "/assistant")
		"share":
			return path.replace("/share", "/microphone")
		_:
			return path

func _convert_joypad_to_switch(path: String):
	path = path.replace("joypad", "switch")
	match path.substr(path.find("/") + 1):
		"a":
			return path.replace("/a", "/b")
		"b":
			return path.replace("/b", "/a")
		"x":
			return path.replace("/x", "/y")
		"y":
			return path.replace("/y", "/x")
		"lb":
			return path.replace("/lb", "/l")
		"rb":
			return path.replace("/rb", "/r")
		"lt":
			return path.replace("/lt", "/zl")
		"rt":
			return path.replace("/rt", "/zr")
		"select":
			return path.replace("/select", "/minus")
		"start":
			return path.replace("/start", "/plus")
		"share":
			return path.replace("/share", "/square")
		# The Switch art has no stick-click icons; show the stick itself.
		"l_stick_click":
			return path.replace("/l_stick_click", "/l_stick")
		"r_stick_click":
			return path.replace("/r_stick_click", "/r_stick")
		_:
			return path

func _convert_joypad_to_xbox360(path: String):
	path = path.replace("joypad", "xbox360")
	match path.substr(path.find("/") + 1):
		"select":
			return path.replace("/select", "/back")
		_:
			return path

func _convert_joypad_to_xbox_modern(path: String):
	match path.substr(path.find("/") + 1):
		"select":
			return path.replace("/select", "/view")
		"start":
			return path.replace("/start", "/menu")
		_:
			return path

func _convert_joypad_to_xboxone(path: String):
	return _convert_joypad_to_xbox_modern(path.replace("joypad", "xboxone"))
