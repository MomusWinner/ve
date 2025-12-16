package main

import "../eldr"
import gfx "../eldr/graphics"
import "core:fmt"
import "core:log"
import "core:mem"

current_scene: Scene

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	eldr.init(
		nil,
		fixed_update,
		update,
		draw,
		destroy,
		{gfx = {swapchain_sample_count = ._4}, window = {width = 800, height = 400, title = "VulkanTest"}},
	)

	current_scene = create_model_scene()
	// current_scene = create_postprocessing_scene()
	// current_scene = create_text_scene()
	// current_scene = create_empty_scene()

	current_scene.init(&current_scene)

	eldr.run()

	log.info("Successfuly close")
}


fixed_update :: proc(user_data: rawptr) {
}

update :: proc(user_data: rawptr) {
	if (eldr.is_key_pressed(.R)) {
		gfx.hot_reload_shaders()
	}

	if (eldr.is_key_pressed(.Escape)) {
		eldr.close()
	}

	current_scene.update(&current_scene)
}

draw :: proc(user_data: rawptr) {
	current_scene.draw(&current_scene)
}

destroy :: proc(user_data: rawptr) {
	current_scene.destroy(&current_scene)
}
