package bench

// oecs implementation of CASES.md. Run with: just oecs

main :: proc() {
	context.allocator = counting_allocator()

	cases := make([dynamic]Case)
	append(&cases, ..flat_cases)
	tree := shape_cases(.Tree, "tree")
	forest := shape_cases(.Forest, "forest")
	chain := shape_cases(.Chain, "chain")
	append(&cases, ..tree[:])
	append(&cases, ..forest[:])
	append(&cases, ..chain[:])

	run("oecs", cases[:])
}
