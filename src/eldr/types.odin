package eldr

import "common"
import gfx "graphics"

vec2 :: common.vec2
vec3 :: common.vec3
vec4 :: common.vec4
color :: common.color
Vertex :: common.Vertex
Image :: common.Image


Camera :: gfx.Camera

Texture :: gfx.Texture
Texture_Handle :: gfx.Texture_Handle

Transform :: gfx.Transform

Material :: gfx.Material

Pipeline :: gfx.Pipeline
Pipeline_Handle :: gfx.Pipeline_Handle
Create_Pipeline_Info :: gfx.Create_Pipeline_Info
Pipeline_Set_Info :: gfx.Pipeline_Set_Info
Pipeline_Set_Binding_Info :: gfx.Pipeline_Set_Binding_Info
Pipeline_Stage_Info :: gfx.Pipeline_Stage_Info

Model :: gfx.Model
Frame_Data :: gfx.Frame_Data
Frame_Status :: gfx.Frame_Status

Create_Font_Info :: gfx.Create_Font_Info
Font :: gfx.Font
Text :: gfx.Text
CharacterRegion :: gfx.CharacterRegion

Surface :: gfx.Surface
Surface_Handle :: gfx.Surface_Handle

Command_Buffer :: gfx.Command_Buffer
Gfx_Size :: gfx.Device_Size
Pipeline_Stage_Flags :: gfx.Pipeline_Stage_Flags
Sync_Data :: gfx.Sync_Data
Semaphore :: gfx.Semaphore
Vertex_Input_Binding_Description :: gfx.Vertex_Input_Binding_Description
Vertex_Input_Attribute_Description :: gfx.Vertex_Input_Attribute_Description
Vertex_Input_Description :: gfx.Vertex_Input_Description
