if has('macunix')
    " Disable GCC and clang on macOS
    let b:ale_linters_ignore = ['gcc', 'clang']
    " let b:ale_linters_ignore += ['cppcheck']

    " This is macOS specific
    let g:ale_cpp_ccls_init_options = {
                \   'cache': {
                \       'directory': '/tmp/ccls/cache'
                \   },
                \   'clang': {
                \        'extraArgs': [
                \               '-isysroot', '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include',
                \               '-isystem', '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include',
                \               '-isystem', '/Library/Developer/CommandLineTools/usr/include/c++/v1'
                \        ],
                \   },
                \ }
end

if executable('astyle')
    let b:ale_fixers = ['aldur#ale_fixers#astyle']
endif

