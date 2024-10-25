lua <<EOF
vim.filetype.add({
    pattern = {
        [".*%.env"] = 'env'
    },
})
EOF
