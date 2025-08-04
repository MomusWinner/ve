#+private
package graphic

_create_pipeline_manager :: proc() -> ^PipelineManager {
	return new(PipelineManager)
}

_destroy_pipeline_mananger :: proc(g: ^Graphic) {
	pm := g.pipeline_manager
	for name, pipeline in pm.pipeline_by_name {
		destroy_pipline(g, pipeline)
	}
	delete(pm.pipeline_by_name)
}

_registe_pipeline :: proc(pm: ^PipelineManager, name: string, pipeline: ^Pipeline) -> bool {
	_, ok := pm.pipeline_by_name[name]
	if ok {
		return false
	}

	pm.pipeline_by_name[name] = pipeline
	return true
}

_get_pipeline_by_name :: proc(pm: ^PipelineManager, name: string) -> (^Pipeline, bool) {
	return pm.pipeline_by_name[name]
}

_pipeline_manager_hot_reload :: proc(pm: ^PipelineManager, g: ^Graphic) {
	for name, pipeline in pm.pipeline_by_name {
		pipeline_info: ^CreatePipelineInfo

		_reload_pipeline(g, pipeline)
	}
}
