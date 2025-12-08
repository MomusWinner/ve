package eldr

import "common"
import gfx "graphics"
import "vendor:glfw"

vec2 :: common.vec2
vec3 :: common.vec3
vec4 :: common.vec4
ivec2 :: common.ivec2
ivec3 :: common.ivec3
ivec4 :: common.ivec4
color :: common.color
Vertex :: common.Vertex
Image :: common.Image

// Graphics_Init_Info :: gfx.Graphics_Init_Info
// Graphics_Limits :: gfx.Graphics_Limits
//
// Camera :: gfx.Camera
//
// Texture :: gfx.Texture
// Texture_Handle :: gfx.Texture_Handle
//
// Gfx_Transform :: gfx.Gfx_Transform
//
// Material :: gfx.Material
//
// Pipeline :: gfx.Pipeline
// Pipeline_Handle :: gfx.Pipeline_Handle
// Create_Pipeline_Info :: gfx.Create_Pipeline_Info
// Pipeline_Set_Info :: gfx.Pipeline_Set_Info
// Pipeline_Set_Binding_Info :: gfx.Pipeline_Set_Binding_Info
// Pipeline_Stage_Info :: gfx.Pipeline_Stage_Info
//
// Model :: gfx.Model
// Frame_Data :: gfx.Frame_Data
// Frame_Status :: gfx.Frame_Status
//
// Create_Font_Info :: gfx.Create_Font_Info
// Font :: gfx.Font
// Text :: gfx.Text
// CharacterRegion :: gfx.CharacterRegion
//
// Surface :: gfx.Surface
// Surface_Handle :: gfx.Surface_Handle
//
// Sample_Count_Flag :: gfx.Sample_Count_Flag
// Command_Buffer :: gfx.Command_Buffer
// Gfx_Size :: gfx.Device_Size
// Pipeline_Stage_Flags :: gfx.Pipeline_Stage_Flags
// Sync_Data :: gfx.Sync_Data
// Semaphore :: gfx.Semaphore
// Vertex_Input_Binding_Description :: gfx.Vertex_Input_Binding_Description
// Vertex_Input_Attribute_Description :: gfx.Vertex_Input_Attribute_Description
// Vertex_Input_Description :: gfx.Vertex_Input_Description

game_event_proc :: proc(user_data: rawptr)

Game_Time :: struct {
	total_game_time:         f64,
	delta_time:              f32,
	target_time:             f32,
	fixed_target_time:       f32,
	previous_frame:          f64,
	fixed_update_total_time: f64,
}

Eldr :: struct {
	window:            glfw.WindowHandle,
	should_close:      bool,
	game_time:         Game_Time,
	user_data:         rawptr,
	fixed_update_proc: game_event_proc,
	update_proc:       game_event_proc,
	draw_proc:         game_event_proc,
	destroy_proc:      game_event_proc,
}

Eldr_Info :: struct {
	gfx:    gfx.Graphics_Init_Info,
	window: struct {
		title:  string,
		width:  i32,
		height: i32,
	},
}
