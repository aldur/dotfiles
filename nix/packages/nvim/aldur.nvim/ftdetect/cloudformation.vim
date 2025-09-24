" This will make `*/cloudformation/*.yaml` file inherit from `yaml`, so we can run
" specific linters.
lua <<EOF
vim.filetype.add({
    pattern = {
        ["cloudformation/.*%.yaml"] = 'yaml.cloudformation'
    },
})
EOF
