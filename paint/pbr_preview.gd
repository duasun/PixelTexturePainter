class_name PBRPreview
extends RefCounted
## Builds a bounded-size viewport preview off the UI thread. Export uses full resolution.
static func build(progress: BackgroundJob.JobProgress, document: PaintDocument) -> Dictionary:
	var maps := {}
	var channels := ["albedo","roughness","metallic","normal","ao","emission"]
	var limit := 1024
	for i in channels.size():
		if progress.report(float(i)/channels.size(),"Preparing lit material preview…"): return {"cancelled":true}
		var channel: String = channels[i]
		var result := ProjectIO.render_image(progress,document,channel)
		if not result.has("image"): return result
		var image: Image = result.image
		if image.get_width()>limit or image.get_height()>limit:
			var factor := minf(float(limit)/image.get_width(),float(limit)/image.get_height())
			image.resize(maxi(1,roundi(image.get_width()*factor)),maxi(1,roundi(image.get_height()*factor)),Image.INTERPOLATE_NEAREST)
		maps[channel] = image
	return {"maps":maps}
