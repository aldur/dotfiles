-- gopls resolves its root by shelling out to `go env GOMODCACHE`, before the
-- server is ever spawned: with no toolchain on PATH that throws out of
-- nvim-lspconfig's `root_dir` and opening a Go file dumps a stack trace
-- instead of attaching. The editor ships the server only — projects bring the
-- toolchain through direnv (see runtime.nix) — so enable it exactly when the
-- toolchain that resolution needs is there.
return {
	{
		"neovim/nvim-lspconfig",
		opts = function(_, opts)
			if vim.fn.executable("go") == 0 then
				opts.servers = opts.servers or {}
				opts.servers.gopls = vim.tbl_deep_extend("force", opts.servers.gopls or {}, { enabled = false })
			end
		end,
	},
}
