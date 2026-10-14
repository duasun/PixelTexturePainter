class_name PainterConfig
extends RefCounted

## Per-user workspace preferences. Project paint data stays in .rtpaint files.
var path := "user://painter.cfg"
var data := ConfigFile.new()

func load_settings() -> void:
	data = ConfigFile.new()
	if data.load(path) == OK:
		return
	# Preserve the older splitter settings when this version first creates painter.cfg.
	var old := ConfigFile.new()
	if old.load("user://workspace_layout.cfg") == OK:
		for key in ["palette_offset", "inspector_offset"]:
			if old.has_section_key("panels", key):
				data.set_value("panels", key, old.get_value("panels", key))

func get_setting(section: String, key: String, fallback: Variant) -> Variant:
	return data.get_value(section, key, fallback)

func set_setting(section: String, key: String, value: Variant) -> void:
	data.set_value(section, key, value)

func save_settings() -> Error:
	return data.save(path)
