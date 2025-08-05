#+private
package graphics

_create_pipeline_manager :: proc() -> ^Pipeline_Manager {
	return new(Pipeline_Manager)
}

_destroy_pipeline_mananger :: proc(g: ^Graphics) {
	pm := g.pipeline_manager
	for name, pipeline in pm.pipeline_by_name {
		destroy_pipline(g, pipeline)
	}
	delete(pm.pipeline_by_name)
}

_registe_pipeline :: proc(pm: ^Pipeline_Manager, name: string, pipeline: ^Pipeline) -> bool {
	_, ok := pm.pipeline_by_name[name]
	if ok {
		return false
	}

	pm.pipeline_by_name[name] = pipeline
	return true
}

_get_pipeline_by_name :: proc(pm: ^Pipeline_Manager, name: string) -> (^Pipeline, bool) {
	return pm.pipeline_by_name[name]
}

_pipeline_manager_hot_reload :: proc(pm: ^Pipeline_Manager, g: ^Graphics) {
	for name, pipeline in pm.pipeline_by_name {
		pipeline_info: ^Create_Pipeline_Info

		_reload_pipeline(g, pipeline)
	}
}
