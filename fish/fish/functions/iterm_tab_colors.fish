function iterm_tab_colors
    switch $argv[1]
        case green
            echo -e "\033]6;1;bg;red;brightness;188\a"
            echo -e "\033]6;1;bg;green;brightness;212\a"
            echo -e "\033]6;1;bg;blue;brightness;89\a"
        case red
            echo -e "\033]6;1;bg;red;brightness;236\a"
            echo -e "\033]6;1;bg;green;brightness;118\a"
            echo -e "\033]6;1;bg;blue;brightness;102\a"
        case blue
            echo -e "\033]6;1;bg;red;brightness;107\a"
            echo -e "\033]6;1;bg;green;brightness;163\a"
            echo -e "\033]6;1;bg;blue;brightness;244\a"
        case orange
            echo -e "\033]6;1;bg;red;brightness;227\a"
            echo -e "\033]6;1;bg;green;brightness;143\a"
            echo -e "\033]6;1;bg;blue;brightness;10\a"
        case violet
            echo -e "\033]6;1;bg;red;brightness;186\a"
            echo -e "\033]6;1;bg;green;brightness;147\a"
            echo -e "\033]6;1;bg;blue;brightness;214\a"
        case yellow
            echo -e "\033]6;1;bg;red;brightness;238\a"
            echo -e "\033]6;1;bg;green;brightness;219\a"
            echo -e "\033]6;1;bg;blue;brightness;96\a"
        case reset
            echo -e "\033]6;1;bg;*;default\a"
    end
end

complete -c iterm_tab_colors --no-files -a 'green red blue orange violet yellow reset'
