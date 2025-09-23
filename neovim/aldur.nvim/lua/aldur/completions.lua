local blink = require('blink.cmp')

local default_sources = {
    'lsp', 'path', 'snippets', 'buffer', 'lazydev', 'note_tags'
}
-- TODO: Add note_tags
-- local md_sources = vim.list_extend({"note_tags"}, default_sources)
local md_sources = default_sources

blink.setup {
    -- 'default' (recommended) for mappings similar to built-in completions (C-y to accept, C-n/C-p for up/down)
    -- 'super-tab' for mappings similar to vscode (tab to accept, arrow keys for up/down)
    -- 'enter' for mappings similar to 'super-tab' but with 'enter' to accept
    --
    -- All presets have the following mappings:
    -- C-space: Open menu or open docs if already open
    -- C-e: Hide menu
    -- C-k: Toggle signature help
    --
    -- See the full "keymap" documentation for information on defining your own keymap.
    keymap = {preset = 'default'},

    -- Enable cmdline
    cmdline = {
        enabled = true,
        keymap = {
            -- recommended, as the default keymap will only show and select the next item
            ['<Tab>'] = {'show', 'accept'}
        },
        completion = {menu = {auto_show = true}}
    },

    completion = {
        -- Disable auto brackets
        -- NOTE: some LSPs may add auto brackets themselves anyway
        accept = {auto_brackets = {enabled = false}},

        -- Don't select by default, auto insert on selection
        list = {selection = {preselect = false, auto_insert = true}},

        documentation = {auto_show = true, auto_show_delay_ms = 500},

        menu = {
            -- nvim-cmp style menu
            draw = {
                columns = {
                    {"label", "label_description", gap = 1}, {"kind_icon"},
                    {"source_name"}
                }
            }
        }
    },

    -- Default list of enabled providers defined so that you can extend it
    -- elsewhere in your config, without redefining it, due to `opts_extend`
    sources = {
        default = default_sources,

        per_filetype = {markdown = md_sources, ['markdown.wiki'] = md_sources},

        providers = {
            snippets = {
                min_keyword_length = 2,
                opts = {
                    friendly_snippets = false,
                    search_paths = {require('aldur.snippets').snippets_path()}
                }
            },

            lazydev = {
                name = "LazyDev",
                module = "lazydev.integrations.blink",
                -- make lazydev completions top priority (see `:h blink.cmp`)
                score_offset = 100
            },

            -- Currently disabled
            ripgrep = {
                module = "blink-ripgrep",
                name = "Ripgrep",
                opts = {project_root_fallback = false},
                transform_items = function(_, items)
                    for _, item in ipairs(items) do
                        -- example: append a description to easily distinguish rg results
                        item.labelDetails = {description = "(rg)"}
                    end
                    return items
                end
            },

            note_tags = {
                name = "note_tags",
                module = "aldur.blink.cmp.note_tags"
            }
        }
    },

    -- Blink.cmp uses a Rust fuzzy matcher by default for typo resistance and significantly better performance
    -- You may use a lua implementation instead by using `implementation = "lua"` or fallback to the lua implementation,
    -- when the Rust fuzzy matcher is not available, by using `implementation = "prefer_rust"`
    --
    -- See the fuzzy documentation for more information
    fuzzy = {implementation = "prefer_rust_with_warning"},

    -- Use a preset for snippets, check the snippets documentation for more information
    snippets = {preset = 'default'},

    -- Experimental signature help support
    signature = {enabled = true}
}

