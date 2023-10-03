return {
    -- efm can't ignore exit code for formatters
    formatCommand = "tidy --indent yes --wrap-attributes yes --doctype omit " ..
        " --wrap 100 --quiet yes --show-errors 0 ${INPUT} || true",
    formatStdin = false,
    lintCommand = "tidy --markup no --quiet yes",
    lintStdin = true,
    lintFormats = {
        'line %l column %c - %tarning: %m',
        'line %l column %c - %rror: %m',
        'line %l column %c - %m',
    }
}

