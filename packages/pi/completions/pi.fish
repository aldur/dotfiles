function __dotfiles_pi_models
    set -l provider
    set -l words (commandline -opc)
    for i in (seq (count $words))
        if test "$words[$i]" = --provider
            set provider $words[(math $i + 1)]
        else if string match -q -- '--provider=*' $words[$i]
            set provider (string replace -- '--provider=' '' $words[$i])
        end
    end
    command pi --list-models 2>/dev/null | while read -l line
        set -l row (string split -n ' ' -- $line)
        if test (count $row) -ne 6; or not contains -- $row[5] yes no; or not contains -- $row[6] yes no
            continue
        end
        if test "$argv[1]" = providers
            echo $row[1]
        else if test -z "$provider"
            printf '%s/%s\n' $row[1] $row[2]
        else if test "$provider" = "$row[1]"
            echo $row[2]
        end
    end | sort -u
end

complete -c pi -l provider -x -a '(__dotfiles_pi_models providers)' -d 'Model provider'
complete -c pi -l model -x -a '(__dotfiles_pi_models models)' -d 'Model ID or pattern'
complete -c pi -l models -x -a '(__dotfiles_pi_models models)' -d 'Model patterns for cycling'
complete -c pi -l thinking -x -a 'off minimal low medium high xhigh max' -d 'Thinking level'
complete -c pi -l mode -x -a 'text json rpc' -d 'Output mode'
complete -c pi -l tui-mode -x -a 'fullscreen regular' -d 'Terminal mode'
complete -c pi -s p -l print -d 'Process the prompt and exit'
complete -c pi -s c -l continue -d 'Continue the previous session'
complete -c pi -s r -l resume -d 'Select a session'
complete -c pi -s n -l name -x -d 'Session name'
complete -c pi -l session -r -d 'Session file or ID'
complete -c pi -l session-id -x -d 'Project session ID'
complete -c pi -l fork -r -d 'Session to fork'
complete -c pi -l session-dir -x -a '(__fish_complete_directories)' -d 'Session directory'
complete -c pi -l no-session -d 'Do not save the session'
complete -c pi -l api-key -x -d 'Provider API key'
complete -c pi -l system-prompt -x -d 'System prompt'
complete -c pi -l append-system-prompt -r -d 'Append text or file contents'
complete -c pi -s t -l tools -x -d 'Tools to enable'
complete -c pi -o xt -l exclude-tools -x -d 'Tools to disable'
complete -c pi -o nt -l no-tools -d 'Disable all tools'
complete -c pi -o nbt -l no-builtin-tools -d 'Disable built-in tools'
complete -c pi -s e -l extension -r -d 'Extension file'
complete -c pi -o ne -l no-extensions -d 'Disable extension discovery'
complete -c pi -l no-mcp -d 'Disable MCP support'
complete -c pi -l skill -r -d 'Skill file or directory'
complete -c pi -o ns -l no-skills -d 'Disable skill discovery'
complete -c pi -l prompt-template -r -d 'Prompt template file or directory'
complete -c pi -o np -l no-prompt-templates -d 'Disable prompt template discovery'
complete -c pi -l theme -r -d 'Theme file or directory'
complete -c pi -l use-theme -x -d 'Initial theme name'
complete -c pi -l no-themes -d 'Disable theme discovery'
complete -c pi -o nc -l no-context-files -d 'Disable context file discovery'
complete -c pi -l export -r -d 'Export a session to HTML'
complete -c pi -l list-models -d 'List available models'
complete -c pi -l verbose -d 'Show startup details'
complete -c pi -s a -l approve -d 'Trust project files'
complete -c pi -o na -l no-approve -d 'Ignore project files'
complete -c pi -l offline -d 'Disable startup network operations'
complete -c pi -s h -l help -d 'Show help'
complete -c pi -s v -l version -d 'Show version'
