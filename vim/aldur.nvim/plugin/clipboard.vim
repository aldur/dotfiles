" This is required because we do not expose `/usr/bin` to the PATH.
if has('mac')
    let g:clipboard = {
            \   'name': 'absolute pbcopy/pbpaste',
            \   'copy': {
            \      '+': ["/usr/bin/pbcopy"],
            \      '*': ["/usr/bin/pbcopy"],
            \    },
            \   'paste': {
            \      '+': ["/usr/bin/pbpaste"],
            \      '*': ["/usr/bin/pbpaste"],
            \   },
            \   'cache_enabled': 0,
            \ }
endif
