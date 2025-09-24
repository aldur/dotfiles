return {
    lintStdin = true,
    lintCommand = "cfn-lint -f parseable -",
    lintFormats = {'%f:%l:%c:%*[0-9]:%*[0-9]:%t%n:%m'},
    lintIgnoreExitCode = true
}
