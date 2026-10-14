class_name PaintChannels
extends RefCounted
const IDS := ["albedo", "roughness", "metallic", "normal", "height", "ao", "emission"]
const LABELS := ["Albedo", "Roughness", "Metallic", "Normal", "Height", "AO", "Emission"]
static func label(channel: String) -> String:
	return LABELS[maxi(0, IDS.find(channel))]
static func background(channel: String) -> Color:
	match channel:
		"roughness", "ao": return Color.WHITE
		"normal": return Color8(128,128,255)
		"height": return Color8(128,128,128)
		"metallic", "emission": return Color.BLACK
	return Color.TRANSPARENT
static func scalar(channel: String) -> bool:
	return channel in ["roughness", "metallic", "height", "ao"]
