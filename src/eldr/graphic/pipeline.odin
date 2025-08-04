package graphic

import "core:log"
import vk "vendor:vulkan"

create_pipeline :: proc(g: ^Graphic, create_pipeline_info: ^CreatePipelineInfo) -> bool {
	pipeline, ok := _create_pipeline(g, create_pipeline_info, context.allocator)
	if !ok {
		log.errorf("couldn't load shader", create_pipeline_info.name)
		return false
	}

	r_ok := _registe_pipeline(g.pipeline_manager, pipeline.create_info.name, pipeline)
	if !r_ok {
		log.errorf("pipeline with name (%s) already registered", create_pipeline_info.name)
		return false
	}

	return true
}

destroy_pipline :: proc(g: ^Graphic, pipeline: ^Pipeline) {
	vk.DestroyPipelineLayout(g.device, pipeline.layout, nil)
	vk.DestroyPipeline(g.device, pipeline.pipeline, nil)

	for layout in pipeline.descriptor_set_layouts {
		_destroy_descriptor_set_layout(g, layout)
	}
	delete(pipeline.descriptor_set_layouts)

	_destroy_create_pipeline_info(pipeline.create_info)
}

bind_pipeline :: proc(g: ^Graphic, pipeline_name: string) {
	pipeline, _ := _get_pipeline_by_name(g.pipeline_manager, pipeline_name)
	vk.CmdBindPipeline(g.command_buffer, .GRAPHICS, pipeline.pipeline)
}

bind_descriptor_set :: proc(g: ^Graphic, pipeline_name: string, descriptor_set: [^]vk.DescriptorSet) {
	pipeline, _ := _get_pipeline_by_name(g.pipeline_manager, pipeline_name)
	vk.CmdBindDescriptorSets(g.command_buffer, .GRAPHICS, pipeline.layout, 0, 1, descriptor_set, 0, nil)
}

create_descriptor_set :: proc(
	g: ^Graphic,
	pipeline_name: string,
	set_index: int,
	resources: []PipelineResource,
) -> (
	vk.DescriptorSet,
	bool,
) {
	pipeline, ok := _get_pipeline_by_name(g.pipeline_manager, pipeline_name)
	if !ok {
		log.errorf("pipeline (%s) is not registered yet", pipeline_name)
		return vk.DescriptorSet{}, false
	}

	return _create_descriptor_set(g, pipeline, set_index, resources), true
}
