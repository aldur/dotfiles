-- Skip categories and specs at once.
local extras = {
	{ "go", "lazyvim.plugins.extras.lang.go" },
	{ "json", "lazyvim.plugins.extras.lang.json" },
	{ "markdown", "lazyvim.plugins.extras.lang.markdown" },
	{ "nix", "lazyvim.plugins.extras.lang.nix" },
	{ "python", "lazyvim.plugins.extras.lang.python" },
	{ "rust", "lazyvim.plugins.extras.lang.rust" },
	{ "toml", "lazyvim.plugins.extras.lang.toml" },
	{ "typescript", "lazyvim.plugins.extras.lang.typescript" },
}

local specs = {
	{ import = "lazyvim.plugins.extras.editor.dial" },
}
for _, extra in ipairs(extras) do
	if nixCats(extra[1]) then
		table.insert(specs, { import = extra[2] })
	end
end
return specs
