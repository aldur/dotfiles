require('gen').setup({
    model = "nemotron",
    show_prompt = "full",
    show_model = true,
    no_auto_close = true,
    debug = false,
    display_mode = "split",
    result_filetype = "markdown.gen"
})

vim.api.nvim_create_user_command('GenSelectModel',
                                 function() require("gen").select_model() end,
                                 {})

vim.keymap.set({'n', 'v'}, '<leader>g', '<cmd>Gen <CR>', {noremap = true})

require('gen').prompts['Links_to_References'] = {
    prompt = [[
        Answer ONLY with the result of your task that follows. No additional
        text, no explanation.

        --- Instructions:

        Rewrite the following Markdown by converting any link into references
        syntax.

        --- Example:

        This is a [very long link](https://example.com/foo/bar) where I tell
        you something.

        --- Example result:

        This is a [very long link][example_link] where I tell you something.

        [example_link]: https://example.com/foo/bar

        --- Your task:

        $text
    ]]
}

require('gen').prompts['Explain_Code'] = {
    prompt = [[
        Explain the following code, line by line.

        ```$filetype
        $text
        ```
    ]]
}

require('gen').prompts['Ask'] = {
    prompt = [[
        Regarding the following text, $input:

        ```$filetype
        $text
        ```
    ]]
}
