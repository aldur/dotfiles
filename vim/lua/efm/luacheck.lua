return {
    lintCommand = "luacheck - --read-globals vim --formatter plain --codes --filename ${INPUT}",
    lintStdin = true,
    lintIgnoreExitCode = true,
    lintFormats = {'%f:%l:%c: %m'}
}
