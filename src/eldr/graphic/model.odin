package graphic

import vk "vendor:vulkan"

// TODO:
// draw_model :: proc(g: ^Graphic, vbo: ^Buffer, ebo: ^Buffer) {
// 	offset := vk.DeviceSize{}
// 	vk.CmdBindVertexBuffers(g.command_buffer, 0, 1, &vbo.buffer, &offset)
// 	vk.CmdBindIndexBuffer(g.command_buffer, ebo.buffer, 0, .UINT16)
//
// 	vk.CmdBindDescriptorSets(
// 		g.command_buffer,
// 		.GRAPHICS,
// 		g.pipeline_layout,
// 		0,
// 		1,
// 		&descriptor_set,
// 		0,
// 		nil,
// 	)
// 	// vk.CmdDraw(gr.command_buffer, 3, 1, 0, 0)
// 	vk.CmdDrawIndexed(g.command_buffer, cast(u32)len(model.indices), 1, 0, 0, 0)
// }
