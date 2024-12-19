if has('mac')
    let g:investigate_use_command_for_markdown = 0
    let g:investigate_use_dash_for_markdown = 0
    let g:investigate_use_url_for_markdown = 1
    let g:investigate_url_for_markdown='dict://^s'
endif

" Alias markdown.wiki to markdown
let g:investigate_syntax_for_markdownwiki = 'markdown'
