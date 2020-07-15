" Source: https://gist.github.com/romainl/379904f91fa40533175dfaec4c833f2f
function! aldur#colors#customize_molokai() abort
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

    " In LaTeX, the arguments of the `begin` and `end` names will be purple
    highlight link texBeginEndName Constant

    " In C, the types are not highlighted
    highlight link cStorageClass Keyword
    highlight link cPreCondit Normal
    highlight link cDefine Function
    highlight link cType Identifier
    highlight link cppType cType
endfunction
