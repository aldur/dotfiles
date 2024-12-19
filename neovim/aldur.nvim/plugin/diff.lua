require("diffview").setup({
    diff_binaries = false, -- Show diffs for binaries
    enhanced_diff_hl = true, -- See |diffview-config-enhanced_diff_hl|
    use_icons = false, -- Requires nvim-web-devicons
    show_help_hints = true, -- Show hints for how to open the help panel
    watch_index = true, -- Update views and index buffers when the git index changes.
    view = {
        default = {
            -- Config for changed files, and staged files in diff views.
            layout = "diff2_horizontal",
            disable_diagnostics = true, -- Temporarily disable diagnostics for diff buffers while in the view.
            winbar_info = false -- See |diffview-config-view.x.winbar_info|
        },
        default_args = { -- Default args prepended to the arg-list for the listed commands
            DiffviewOpen = {},
            DiffviewFileHistory = {}
        },
        hooks = {}, -- See |diffview-config-hooks|
        keymaps = {
            disable_defaults = false, -- Disable the default keymaps
            view = {{"n", "<leader>b", false}},
            file_panel = {{"n", "<leader>b", false}}
        }
    }
})
