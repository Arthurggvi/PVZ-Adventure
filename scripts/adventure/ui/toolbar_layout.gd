## Pure viewport-space geometry for the persistent right-edge map toolbar.
## All positions are native viewport coordinates, independent of scene ArtCanvas.
extends RefCounted

const DESIGN_SIZE := Vector2(1920.0, 1080.0)
const BAR_SIZE := Vector2(1080.0, 176.0)
const HANDLE_WIDTH := 94.0

static func calculate(viewport_size: Vector2, expanded: bool) -> Dictionary:
	assert(viewport_size.x > 0.0 and viewport_size.y > 0.0)
	var factor := minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y)
	var handle := Vector2(
		viewport_size.x - HANDLE_WIDTH * factor,
		viewport_size.y - BAR_SIZE.y * factor
	)
	return {
		"scale": factor,
		"handle": handle,
		"panel": handle - Vector2(BAR_SIZE.x * factor if expanded else 0.0, 0.0)
	}
