@tool
extends Resource
class_name ControllerSettings

## Bonkraiders keeps only the icon sets it ships: PS4, PS5, Switch,
## Xbox 360 and Xbox One, plus keyboard and mouse. The numbers are the
## ones upstream uses, so saved settings (settings.tres) keep their meaning.
enum Devices {
	NONE = -1,
	PS4 = 3,
	PS5 = 4,
	SWITCH = 7,
	XBOX360 = 9,
	XBOXONE = 10,
}

## General addon settings
@export_subgroup("General")

## Controller type to fallback to if automatic
## controller detection fails
@export var joypad_fallback : Devices = Devices.XBOX360

## Controller deadzone for triggering an icon remap when input
## is analogic (movement sticks or triggers)
@export_range(0.0, 1.0) var joypad_deadzone : float = 0.5

## Allow mouse movement to trigger an icon remap
@export var allow_mouse_remap : bool = true

## Minimum mouse "instantaneous" movement for
## triggering an icon remap
@export_range(0, 10000) var mouse_min_movement : int = 200

## Settings related to advanced custom assets usage and remapping
@export_subgroup("Custom assets")

## Custom asset lookup folder for custom icons
@export_dir var custom_asset_dir : String = ""

## Custom generic joystick mapper script
@export var custom_mapper : Script

## Custom icon file extension
@export var custom_file_extension : String = ""

## Custom settings related to any text rendering required on prompts
@export_subgroup("Text Rendering")

## Custom LabelSettings. If unset, uses engine default settings.
@export var custom_label_settings : LabelSettings
