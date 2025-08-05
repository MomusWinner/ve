package graphics

pipeline_hot_reload :: proc(g: ^Graphics) {
	_pipeline_manager_hot_reload(g.pipeline_manager, g)
}
