# TODO: test compilation flags

odin run ./src -o:speed -out=Craftorio_release \
	-no-bounds-check \
	-disable-assert \
	$*
