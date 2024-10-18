-- brew install markdownlint-cli
return {
    lintCommand = "markdownlint -s",
    lintStdin = true,
    -- stdin:15:1 MD034/no-bare-urls Bare URL used [Context: "https://google.com"]
    lintFormats = {'%f:%l:%c %m'}
}
