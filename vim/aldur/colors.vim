function! aldur#colors#customize_sonokai() abort
    " From the `sonokai` docs.

    " Link a highlight group to a predefined highlight group.
    " See `colors/sonokai.vim` for all predefined highlight groups.
    " highlight! link groupA groupB
    " highlight! link groupC groupD

    " Initialize the color palette.
    " The parameter is a valid value for `g:sonokai_style`,
    let l:palette = sonokai#get_palette(
                \ get(g:, 'sonokai_style', "default"),
                \ get(g:, 'soookai_colors_override', {})
                \ )
    " Define a highlight group.
    " The first parameter is the name of a highlight group,
    " the second parameter is the foreground color,
    " the third parameter is the background color,
    " the fourth parameter is for UI highlighting which is optional,
    " and the last parameter is for `guisp` which is also optional.
    " See `autoload/sonokai.vim` for the format of `l:palette`.

    " TODO is bold and yellow
    call sonokai#highlight('Todo', l:palette.yellow, l:palette.bg0, 'bold')
    " NOTE is bold and blue
    call sonokai#highlight('Note', l:palette.blue, l:palette.bg0, 'bold')
    " DEBUG is bold and red
    call sonokai#highlight('Debug', l:palette.red, l:palette.bg0, 'bold')
    " DONE is bold and green
    call sonokai#highlight('Done', l:palette.green, l:palette.bg0, 'bold')
endfunction
