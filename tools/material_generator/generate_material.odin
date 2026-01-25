package material_generator

import "core:flags"
import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:terminal/ansi"

MATERIAL_ATTRIBUTE :: "material"
UNIFORM_BUFFER_ATTRIBUTE :: "uniform_buffer"


Field_Type :: enum {
	None,
	Int,
	Bool,
	Float,
	Vector2,
	Vector3,
	Vector4,
	Mat4,
	Texture_Handle,
	Buffer_Handle,
}

Struct_Type :: enum {
	None,
	Material,
	Uniform_Buffer,
}

Field :: struct {
	name: string,
	type: Field_Type,
}

Struct :: struct {
	name:   string,
	type:   Struct_Type,
	fields: []Field,
}

Package_Info :: struct {
	alias: string,
	path:  string,
}

main :: proc() {
	Options :: struct {
		src_dir:          string `args:"required" usage:"Package directory containing original material types @(material)."`,
		outpute_glsl_dir: string `args:"required" usage:"Shaders directory."`,
		gfx_import:       string `usage:"Path to graphics package. (gfx ve/graphics, ve/graphics, <empty>)"`,
	}

	opt: Options
	style: flags.Parsing_Style = .Odin

	flags.parse_or_exit(&opt, os.args, style)
	gfx_pkg_info := parse_package_info(opt.gfx_import)

	generate_materials(
		filepath.clean(opt.src_dir, context.temp_allocator),
		filepath.join({opt.outpute_glsl_dir, "gen_types.h"}, context.temp_allocator),
		filepath.join({opt.src_dir, "gen_materials.odin"}, context.temp_allocator),
		gfx_pkg_info,
	)
}

generate_materials :: proc(
	src_path: string,
	outpute_glsl_path: string,
	outpute_odin_path: string,
	gfx_package: Package_Info,
	loc := #caller_location,
) {
	if !os.is_dir_path(src_path) {
		error("Unable to find directory src-path: \"%s\"", src_path)
	}

	if !os.is_dir_path(filepath.dir(outpute_glsl_path, context.temp_allocator)) {
		error("Unable to find outpute-glsl dir: \"%s\"", outpute_glsl_path)
	}

	if !os.is_dir_path(filepath.dir(outpute_odin_path, context.temp_allocator)) {
		error("Unable to find outpute-odin dir: \"%s\"", outpute_odin_path)
	}

	c := context
	context.allocator = context.temp_allocator

	pkg, ok := parser.parse_package_from_path(src_path)
	if !ok {
		error("Failed to parse package by path %", src_path)
	}

	structures := parse_structures(pkg, loc)
	context = c

	generate_glsl(outpute_glsl_path, structures, loc)
	generate_odin(outpute_odin_path, pkg.name, structures, gfx_package)
}

generate_glsl :: proc(path: string, structs: []Struct, loc := #caller_location) {
	f, ok := os.open(path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
	defer os.close(f)

	if ok != nil {
		error("Failed opening '%s' folder", path)
	}

	fmt.fprintln(f, "#include \"buildin:defines/bindless.h\"\n")

	for s in structs {
		glsl_struct_name, ok := strings.replace_all(s.name, "_", "")
		assert(ok)
		fmt.fprintfln(f, "RegisterUniform(%s, {{", glsl_struct_name)

		for field in calculate_std140_layout(s.fields) {
			assert(field.type != .None)
			fmt.fprintfln(f, "	%s %s;", field_type_to_glsl_type(field.type), field.name)
		}

		fmt.fprintfln(f, "}});")

		switch s.type {
		case .None:
		case .Material:
			func_name, r_ok := strings.replace_all(glsl_struct_name, "Material", "")
			fmt.fprintfln(
				f,
				"#define getMtrl{1:s}() GetResource({0:s}, PushConstants.material)",
				glsl_struct_name,
				func_name,
			)
		case .Uniform_Buffer:
			func_name, r_ok := strings.replace_all(glsl_struct_name, "Ubo", "")
			fmt.fprintfln(f, "#define getUbo{1:s}(index) GetResource({0:s}, index)", glsl_struct_name, func_name)
		}
	}
}

generate_odin :: proc(
	path: string,
	package_name: string,
	structs: []Struct,
	gfx_pkg_info: Package_Info,
	loc := #caller_location,
) {
	f, ok := os.open(path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
	defer os.close(f)

	if ok != nil {
		error("Failed opening '%s' folder", path)
	}

	fmt.fprintfln(f, "package %s\n", package_name)
	fmt.fprintfln(f, "import \"core:math/linalg/glsl\"")
	if gfx_pkg_info.path != "" {
		fmt.fprintfln(f, "import {0:s} \"{1:s}\"", gfx_pkg_info.alias, gfx_pkg_info.path)
	}

	gfx_pref := ""

	if gfx_pkg_info.alias != "" {
		gfx_pref = fmt.aprintf("%s.", gfx_pkg_info.alias)
	} else if gfx_pkg_info.path != "" {
		path := strings.split(gfx_pkg_info.path, "/")
		gfx_pref = fmt.aprintf("%s.", path[len(path) - 1])
	}

	for s in structs {
		switch s.type {
		case .None:
		case .Material:
			generate_material_data(f, s, gfx_pref)
		case .Uniform_Buffer:
			generate_uniform_buffer_data(f, s, gfx_pref)
		}
	}
}

generate_material_data :: proc(f: os.Handle, s: Struct, gfx_pref: string) {
	fmt.fprintfln(f, `

///////////////////////////
// %s
//////////////material/////

	`, s.name)
	fmt.fprintfln(f, "__%s_Data :: struct {{", s.name)

	for field in calculate_std140_layout(s.fields) {
		print_data_field_for_odin(f, field, gfx_pref)
	}
	fmt.fprintln(f, "} \n")

	proc_postfix := struct_name_to_postfix(s.name, "_material", context.temp_allocator)

	fmt.fprintfln(
		f,
		`
create_mtrl_{0:s} :: proc(pipeline_h: {2:s}Render_Pipeline_Handle, loc := #caller_location) -> {2:s}Material_Handle {{
	m := {2:s}Material{{}}
	m.pipeline_h = pipeline_h
	material_data := new({1:s})
	m.data = material_data
	m.type = typeid_of(^{1:s})
	m.dirty = true
	m.apply = mtrl_{0:s}_apply

	buffer := {2:s}create_uniform_buffer(size_of(__{1:s}_Data), loc)
	m.buffer_h = {2:s}store_buffer(buffer, loc)
`,
		proc_postfix,
		s.name,
		gfx_pref,
	)

	for field in s.fields {
		default_value, has_default_value := get_field_type_default_value(field.type, gfx_pref).?
		if !has_default_value do continue

		fmt.fprintfln(f, "	material_data.{0:s} = {1:s}", field.name, default_value)
	}

	fmt.fprintfln(f, `
	return {0:s}store_material(m) 
}}`, gfx_pref)

	for field in s.fields {
		fmt.fprintf(
			f,
			`
mtrl_{0:s}_set_{2:s} :: proc(m: ^{4:s}Material, {2:s}: {3:s}, loc := #caller_location) {{
	assert(m != nil, loc = loc)
	assert(m.type == typeid_of(^{1:s}), loc = loc)
	mat := cast(^{1:s})m.data
	mat.{2:s} = {2:s}
	m.dirty = true
}}
mtrl_{0:s}_get_{2:s} :: proc(m: {4:s}Material, loc := #caller_location) -> {3:s}{{
	assert(m.type == typeid_of(^{1:s}), loc = loc)
	mat := cast(^{1:s})m.data
	return mat.{2:s}
}}`,
			proc_postfix,
			s.name,
			field.name,
			field_type_to_odin_type(field.type, gfx_pref),
			gfx_pref,
		)
	}

	fmt.fprintf(
		f,
		`
mtrl_{0:s}_apply :: proc(m: ^{2:s}Material, loc := #caller_location) {{
	assert(m != nil, loc = loc)
	assert(m.type == typeid_of(^{1:s}), loc = loc)
	if !m.dirty do return
	mat := cast(^{1:s})m.data
	mtrl_data := __{1:s}_Data {{
	`,
		proc_postfix,
		s.name,
		gfx_pref,
	)

	for field in s.fields {
		print_field_to_data_field(f, "mat", field, gfx_pref)
	}

	fmt.fprintf(
		f,
		`
	}}

	buffer := {1:s}get_buffer_h(m.buffer_h, loc)
	{1:s}fill_buffer(buffer, size_of(__{0:s}_Data), &mtrl_data, 0, loc)
	m.dirty = false
}}`,
		s.name,
		gfx_pref,
	)
}

generate_uniform_buffer_data :: proc(f: os.Handle, s: Struct, gfx_pref: string) {
	fmt.fprintfln(f, `

///////////////////////////
// %s
//////////unform_buffer////

	`, s.name)
	fmt.fprintfln(f, "__%s_Data :: struct {{", s.name)

	for field in calculate_std140_layout(s.fields) {
		print_data_field_for_odin(f, field, gfx_pref)
	}
	fmt.fprintln(f, "} \n")

	proc_postfix := struct_name_to_postfix(s.name, "_ubo", context.temp_allocator)

	fmt.fprintfln(
		f,
		`
create_ubo_{0:s} :: proc(loc := #caller_location) -> {2:s}Uniform_Buffer_Handle {{
	u: {2:s}Uniform_Buffer
	uniform_data := new({1:s})
	u.data = uniform_data
	u.type = typeid_of(^{1:s})
	u.dirty = true
	u.apply = ubo_{0:s}_apply

	buffer := {2:s}create_uniform_buffer(size_of(__{1:s}_Data), loc)
	u.buffer_h = {2:s}store_buffer(buffer, loc)
`,
		proc_postfix,
		s.name,
		gfx_pref,
	)

	for field in s.fields {
		default_value, has_default_value := get_field_type_default_value(field.type, gfx_pref).?
		if !has_default_value do continue

		fmt.fprintfln(f, "	uniform_data.{0:s} = {1:s}", field.name, default_value)
	}

	fmt.fprintfln(f, `
	return {0:s}store_uniform_buffer(u)
}}
	`, gfx_pref)

	for field in s.fields {
		fmt.fprintf(
			f,
			`
ubo_{0:s}_set_{2:s} :: proc(u: ^{4:s}Uniform_Buffer, {2:s}: {3:s}, loc := #caller_location) {{
	assert(u != nil, loc = loc)
	assert(u.type == typeid_of(^{1:s}), loc = loc)
	ubo := cast(^{1:s})u.data
	ubo.{2:s} = {2:s}
	u.dirty = true
}}
ubo_{0:s}_get_{2:s} :: proc(u: {4:s}Uniform_Buffer, loc := #caller_location) -> {3:s}{{
	assert(u.type == typeid_of(^{1:s}), loc = loc)
	ubo := cast(^{1:s})u.data
	return ubo.{2:s}
}}`,
			proc_postfix,
			s.name,
			field.name,
			field_type_to_odin_type(field.type, gfx_pref),
			gfx_pref,
		)
	}

	fmt.fprintf(
		f,
		`
ubo_{0:s}_apply :: proc(u: ^{2:s}Uniform_Buffer, loc := #caller_location) {{
	assert(u != nil, loc = loc)
	assert(u.type == typeid_of(^{1:s}), loc = loc)
	if !u.dirty do return
	ubo := cast(^{1:s})u.data
	ubo_data := __{1:s}_Data {{
	`,
		proc_postfix,
		s.name,
		gfx_pref,
	)

	for field in s.fields {
		print_field_to_data_field(f, "ubo", field, gfx_pref)
	}

	fmt.fprintf(
		f,
		`
	}}

	buffer := {1:s}get_buffer_h(u.buffer_h, loc)
	{1:s}fill_buffer(buffer, size_of(__{0:s}_Data), &ubo_data, 0, loc)
	u.dirty = false
}}`,
		s.name,
		gfx_pref,
	)
}

print_field_to_data_field :: proc(f: os.Handle, source_name: string, field: Field, gfx_pref: string) {
	if (field.type == .Texture_Handle) {
		fmt.fprintfln(
			f,
			"	{0:s} = {2:s}.{0:s}.index if {1:s}has_texture_h({2:s}.{0:s}) else max(u32),",
			field.name,
			gfx_pref,
			source_name,
		)
	} else if (field.type == .Buffer_Handle) {
		fmt.fprintfln(
			f,
			"	{0:s} = {2:s}.{0:s}.index if {1:s}has_buffer_h({2:s}.{0:s}) else max(u32),",
			field.name,
			gfx_pref,
			source_name,
		)
	} else {
		fmt.fprintfln(f, "	{0:s} = {1:s}.{0:s},", field.name, source_name)
	}
}

get_field_type_default_value :: proc(field_type: Field_Type, gfx_pref: string) -> Maybe(string) {
	switch field_type {
	case .None, .Int, .Bool, .Float, .Vector2, .Vector3, .Vector4, .Mat4:
		return nil
	case .Texture_Handle:
		return fmt.tprintf("%sNil_Texture_Handle", gfx_pref)
	case .Buffer_Handle:
		return fmt.tprintf("%sNil_Buffer_Handle", gfx_pref)
	}
	return nil
}

print_data_field_for_odin :: proc(f: os.Handle, field: Field, gfx_pref: string) {
	assert(field.type != .None)
	if (field.type == .Texture_Handle || field.type == .Buffer_Handle) {
		fmt.fprintfln(f, "	%s: u32,", field.name)
	} else {
		fmt.fprintfln(f, "	%s: %s,", field.name, field_type_to_odin_type(field.type, gfx_pref))
	}
}

struct_name_to_postfix :: proc(name: string, postfix: string, allocator := context.allocator) -> string {
	lower_name := strings.to_lower(name, allocator)
	if len(lower_name) >= len(postfix) && lower_name[len(lower_name) - len(postfix):] == postfix {
		return lower_name[:len(lower_name) - len(postfix)]
	}
	return lower_name
}

parse_structures :: proc(pkg: ^ast.Package, loc := #caller_location) -> []Struct {
	ok: bool
	structures := make([dynamic]Struct)

	for path, file in pkg.files {
		for decl in file.decls {
			material_struct := Struct{}
			fields := make([dynamic]Field)

			value_decl: ^ast.Value_Decl
			if value_decl, ok = decl.derived.(^ast.Value_Decl); !ok || len(value_decl.values) < 1 {
				continue
			}

			value := value_decl.values[0]

			ast_struct_type: ^ast.Struct_Type
			if ast_struct_type, ok = value.derived.(^ast.Struct_Type); !ok {
				continue
			}
			if ident, ok := value_decl.names[0].derived.(^ast.Ident); ok {
				material_struct.name = ident.name
			}

			struct_type := get_struct_type(value_decl.attributes[:])
			if struct_type == .None {
				continue
			}

			for field_prs in ast_struct_type.fields.list {
				field := Field{}
				field_type, field_type_string := parse_field_type(field_prs.type)
				field_name_expr := field_prs.names[0]
				field_name_expr_ident, ok := field_name_expr.derived.(^ast.Ident)
				assert(ok, loc = loc)
				field.name = field_name_expr_ident.name

				if field_type == .None {
					error(
						"Unprocessable Field Type Detected\n" +
						"File: %s\n" +
						"Structure: %s\n" +
						"Field: %s\n" +
						"Type: %s",
						path,
						material_struct.name,
						field.name,
						field_type_string if field_type_string != "" else "unporcessable_type",
					)
				}

				field.type = field_type
				append(&fields, field)
			}

			material_struct.fields = fields[:]
			material_struct.type = struct_type

			append(&structures, material_struct)
		}
	}

	return structures[:]
}

get_struct_type :: proc(attributes: []^ast.Attribute) -> Struct_Type {
	for attribute in attributes {
		for elem in attribute.elems {
			ident, ok := elem.derived.(^ast.Ident)
			if ok {
				if ident.name == MATERIAL_ATTRIBUTE {
					return .Material
				} else if ident.name == UNIFORM_BUFFER_ATTRIBUTE {
					return .Uniform_Buffer
				}
			}
		}
	}

	return .None
}

parse_field_type :: proc(node: ^ast.Expr) -> (Field_Type, string) {
	assert(node != nil)

	field_type: Field_Type = .None
	#partial switch n in node.derived {
	case ^ast.Ident:
		return odin_type_to_field_type(n.name), n.name
	case ^ast.Selector_Expr:
		return odin_type_to_field_type(n.field.name), n.field.name
	case:
		return .None, ""
	}

	return .None, ""
}

calculate_std140_layout :: proc(fields: []Field) -> []Field {
	std140_fields := make([dynamic]Field)
	current_offset := 0

	pad_index := 0

	for field in fields {
		align := get_field_type_base_aligment(field.type)
		size := get_field_type_size(field.type)

		padding := (align - (current_offset % align)) % align

		if padding > 0 {
			assert(padding % 4 == 0, "Padding must be multiple of 4")
			for i in 0 ..< padding / 4 {
				append(&std140_fields, Field{name = fmt.aprintf("pad%d", pad_index), type = .Float})
				pad_index += 1
			}
			current_offset += padding
		}

		append(&std140_fields, field)
		current_offset += size
	}

	final_padding := (16 - (current_offset % 16)) % 16
	for i in 0 ..< final_padding / 4 {
		append(&std140_fields, Field{name = fmt.aprintf("pad%d", pad_index), type = .Float})
		pad_index += 1
	}

	return std140_fields[:]
}

odin_type_to_field_type :: proc(str: string) -> Field_Type {
	switch str {
	case "i32":
		return .Int
	case "f32":
		return .Float
	case "bool":
		return .Bool
	case "vec2":
		return .Vector2
	case "vec3":
		return .Vector3
	case "vec4":
		return .Vector4
	case "mat4":
		return .Mat4
	case "Texture_Handle":
		return .Texture_Handle
	case "Buffer_Handle":
		return .Buffer_Handle
	case:
		return .None
	}
}

field_type_to_glsl_type :: proc(field_type: Field_Type) -> string {
	switch field_type {
	case .None:
		return ""
	case .Int:
		return "int"
	case .Float:
		return "float"
	case .Bool:
		return "bool"
	case .Vector2:
		return "vec2"
	case .Vector3:
		return "vec3"
	case .Vector4:
		return "vec4"
	case .Mat4:
		return "mat4"
	case .Texture_Handle:
		return "uint"
	case .Buffer_Handle:
		return "uint"
	}

	return ""
}

field_type_to_odin_type :: proc(field_type: Field_Type, gfx_pref: string) -> string {
	switch field_type {
	case .None:
		return ""
	case .Int:
		return "i32"
	case .Float:
		return "f32"
	case .Bool:
		return "bool"
	case .Vector2:
		return "glsl.vec2"
	case .Vector3:
		return "glsl.vec3"
	case .Vector4:
		return "glsl.vec4"
	case .Mat4:
		return "glsl.mat4"
	case .Texture_Handle:
		return fmt.aprintf("%sTexture_Handle", gfx_pref)
	case .Buffer_Handle:
		return fmt.aprintf("%sBuffer_Handle", gfx_pref)
	}

	return ""
}

get_field_type_base_aligment :: proc(type: Field_Type) -> int {
	switch type {
	case .None:
		return 0
	case .Float, .Int, .Bool, .Texture_Handle, .Buffer_Handle:
		return 4
	case .Vector2:
		return 8
	case .Vector3, .Vector4, .Mat4:
		return 16
	}
	return 16
}

get_field_type_size :: proc(t: Field_Type) -> int {
	switch t {
	case .None:
		return 0
	case .Float, .Int, .Bool, .Texture_Handle, .Buffer_Handle:
		return 4
	case .Vector2:
		return 8
	case .Vector3:
		return 12
	case .Vector4:
		return 16
	case .Mat4:
		return 64
	}
	return 0
}

parse_package_info :: proc(source: string) -> Package_Info {
	gfx_pkg_info := Package_Info{}

	s, _ := strings.split(source, " ")
	if len(s) > 2 {
		fmt.println(
			`Invalid gfx_import format.
Expected:
	gfx_import = "alias path"
	gfx_import = "path"
	gfx_import = ""

Examples:
	"ve/graphics"
	"gfx ve/graphics"
	""

But got:`,
			source,
		)
	}

	if len(s) == 1 {
		return Package_Info{alias = "", path = source}
	} else if len(s) == 2 {
		return Package_Info{alias = s[0], path = s[1]}
	}
	return Package_Info{}
}

error :: proc(fmt_str: string, args: ..any) {
	RED :: ansi.CSI + ansi.FG_RED + ansi.SGR
	message := fmt.tprintf(fmt_str, ..args)
	fmt.println(RED, message)
	os.exit(1)
}
