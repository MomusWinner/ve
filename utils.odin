package ve

import "common"
import "core:fmt"
import gfx "graphics"

assert_frame_data :: proc(frame_data: gfx.Frame_Data) {
	assert(frame_data.cmd != nil)
}

merge :: common.merge
assert_not_nil :: common.assert_not_nil
