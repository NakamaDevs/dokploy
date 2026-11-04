const assert = require("node:assert/strict");
const fs = require("node:fs");
const { createRequire } = require("node:module");
const path = require("node:path");

const store = path.join(process.argv[2] || process.cwd(), "node_modules/.pnpm");
const grammars = [
	["tree-sitter-json", '{"native":true}'],
	["@tree-sitter-grammars/tree-sitter-yaml", "native: true\n"],
];
for (const [name, source] of grammars) {
	const prefix = `${name.replace("/", "+")}@`;
	const entries = fs
		.readdirSync(store)
		.filter((entry) => entry.startsWith(prefix));
	assert.ok(entries.length, `Missing native grammar: ${name}`);
	for (const entry of entries) {
		const grammarPath = path.join(store, entry, "node_modules", name);
		const grammarRequire = createRequire(
			path.join(grammarPath, "package.json"),
		);
		const Parser = grammarRequire("tree-sitter");
		const parser = new Parser();
		parser.setLanguage(grammarRequire(grammarPath));
		const tree = parser.parse(source);
		assert.equal(tree.rootNode.hasError, false, `${name} failed to parse`);
		console.log(`PASS native parse: ${entry}`);
	}
}
