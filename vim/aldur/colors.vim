" Source: https://gist.github.com/romainl/379904f91fa40533175dfaec4c833f2f
function! aldur#colors#customize_monokai() abort
    " Make SpellBad text have a red underline on GUIs...
    highlight SpellBad ctermfg=231 ctermbg=197 guibg=none guifg=none guisp=#ff005f gui=undercurl

    " ...and SpellRare have a white underline on GUIs.
    highlight SpellRare ctermfg=231 ctermbg=197 guifg=none guibg=none guisp=white gui=undercurl

    " Same for SpellLocal
    highlight SpellLocal cterm=italic ctermfg=235 ctermbg=208 guifg=none guibg=none guisp=#FF9700 gui=undercurl

    " ... and SpellCap
    highlight SpellCap cterm=italic ctermfg=235 ctermbg=208 guifg=none guisp=#FF9700 guibg=none gui=undercurl

    " TODO are bold and yellow.
    highlight Todo cterm=bold ctermfg=228 ctermbg=59 gui=bold guifg=#ffff87 guibg=none

    " Make folds a little lighter `s:light_grey` from `monokay-tasty`
    highlight Folded ctermfg=250 guifg=#bcbcbc

    " In LaTeX, the arguments of the `begin` and `end` names will be purple
    highlight link texBeginEndName Constant

    " In C, the types are not highlighted
    highlight link cStorageClass Keyword
    highlight link cPreCondit Normal
    highlight link cDefine Function
    highlight link cType Identifier
    highlight link cppType cType
endfunction

function! aldur#colors#customize_sonokai() abort
    " From the `sonokai` docs.

    " Link a highlight group to a predefined highlight group.
    " See `colors/sonokai.vim` for all predefined highlight groups.
    " highlight! link groupA groupB
    " highlight! link groupC groupD

    " Initialize the color palette.
    " The parameter is a valid value for `g:sonokai_style`,
    let l:palette = sonokai#get_palette(get(g:, 'sonokai_style', "default"))
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
