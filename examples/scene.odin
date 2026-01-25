package main

Scene :: struct {
	data:    rawptr,
	init:    proc(s: ^Scene),
	update:  proc(s: ^Scene),
	draw:    proc(s: ^Scene),
	destroy: proc(s: ^Scene),
}
