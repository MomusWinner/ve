package graphic

pipeline_hot_reload :: proc(g: ^Graphic) {
	_pipeline_manager_hot_reload(g.pipeline_manager, g)
}
