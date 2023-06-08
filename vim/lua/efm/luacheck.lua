return {
    lintCommand = "pushd $(dirname ${INPUT}) && luacheck --formatter plain --codes ${INPUT}",
    lintFormats = {'%f:%l:%c: %m'}
}
