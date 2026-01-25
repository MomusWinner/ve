APP_NAME := Eldr_Examples
SRC_DIR := examples
BIN_DIR := bin
DEBUG_BIN := $(BIN_DIR)/debug/$(APP_NAME)
RELEASE_BIN := $(BIN_DIR)/release/$(APP_NAME)

ODIN_FLAGS := -custom-attribute:material,uniform_buffer
ODIN_DEBUG_FLAGS := -debug ${ODIN_FLAGS}
ODIN_RELEASE_FLAGS := -o:speed -no-bounds-check -disable-assert ${ODIN_FLAGS}
ODIN := odin

.PHONY: all
all: debug release

.PHONY: debug
debug:
	@echo "Building debug examples ..."
	@mkdir -p $(BIN_DIR)/debug

	$(ODIN) build $(SRC_DIR) -out:$(DEBUG_BIN) ${ODIN_DEBUG_FLAGS}
	@echo "Built: $(DEBUG_BIN)"

.PHONY: release
release:
	@echo "Building release examples ..."
	@mkdir -p $(BIN_DIR)/release
	$(ODIN) build $(SRC_DIR) -out:$(RELEASE_BIN) -o:speed ${ODIN_FLAGS}
	@echo "Built: $(RELEASE_BIN)"

.PHONY: run
run: debug
	@echo "🐢 Running examples $(DEBUG_BIN)..."
	@$(DEBUG_BIN)

.PHONY: run-release
run-release: release
	@echo "🐇 Running example $(RELEASE_BIN)..."
	@$(RELEASE_BIN)

.PHONY: gen
gen:
	@echo "Generating..."
	odin run ./ve/tools/material_generator/ -- \
		-outpute-glsl-dir:assets/shaders/ \
		-src-dir:./examples \
		-gfx-import:"gfx ../ve/graphics"

.PHONY: init-ve
gen-ve:
	@echo "Generating..."
	odin run ./ve/tools/material_generator/ -- \
		-outpute-glsl-dir:assets/buildin/shaders/ \
		-src-dir:./ve/graphics/

.PHONY: clean
clean:
	rm -rf $(BIN_DIR)
