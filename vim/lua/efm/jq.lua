return {
    formatCommand = "jq .",
    formatStdin = true,
    lintCommand = "jq .",
    lintStdin = true,
    lintFormats = {'parse error: %m at line %l, column %c'},
    lintIgnoreExitCode = true
}
