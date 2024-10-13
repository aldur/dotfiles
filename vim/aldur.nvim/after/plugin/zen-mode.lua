local z = require("zen-mode")

local function width_from_columns()
    if vim.o.columns > 200 then return 100 end

    return vim.o.columns * 0.6
end

z.setup({
    window = {
        backdrop = 1, -- shade the backdrop of the Zen window. Set to 1 to keep the same as Normal

        -- height and width can be:
        -- * an absolute number of cells when > 1
        -- * a percentage of the width / height of the editor when <= 1
        -- * a function that returns the width or the height
        width = width_from_columns, -- width of the Zen window
        height = 0.85, -- height of the Zen window

        -- by default, no options are changed for the Zen window
        -- uncomment any of the options below, or add other vim.wo options you want to apply
        options = {
            signcolumn = "no", -- disable signcolumn
            number = false, -- disable number column
            relativenumber = false, -- disable relative numbers
            cursorline = false, -- disable cursorline
            cursorcolumn = false, -- disable cursor column
            foldcolumn = "0", -- disable fold column
            list = false -- disable whitespace characters
        }
    },
    plugins = {
        -- disable some global vim options (vim.o...)
        -- comment the lines to not apply the options
        options = {
            enabled = true,
            ruler = true, -- disables the ruler text in the cmd line area
            showcmd = true -- disables the command in the last line of the screen
        },
        twilight = {enabled = false}, -- enable to start Twilight when zen mode opens
        gitsigns = {enabled = false}, -- disables git signs
        tmux = {enabled = false}, -- disables the tmux statusline
        -- this will change the font size on kitty when in zen mode
        -- to make this work, you need to set the following kitty options:
        -- - allow_remote_control socket-only
        -- - listen_on unix:/tmp/kitty
        kitty = {
            enabled = false,
            font = "+4" -- font size increment
        }
    },
    -- callback where you can add custom code when the Zen window opens
    on_open = function(_)
        -- ZenBg gets computed too early. This re-computes it at the right time.
        vim.cmd("highlight clear ZenBg")
        local config = require("zen-mode.config")
        config.colors(config.options)
    end,
    -- callback where you can add custom code when the Zen window closes
    on_close = function() end
})

-- Allow calling `ZenMode 0.8` to get 80% width window.
vim.api.nvim_create_user_command('ZenMode', function(command)
    local nargs = #command.fargs
    local width = nil
    if nargs > 0 then
        width = command.fargs[1]
        width = tonumber(width)
    end
    if width ~= nil then
        -- If open, re-open it with desired width
        z.close()
        return z.open({window = {width = width}})
    end
    return z.toggle()
end, {nargs = "?"})

vim.keymap.set('n', '<leader>z', "<cmd>ZenModeM<cr>")
