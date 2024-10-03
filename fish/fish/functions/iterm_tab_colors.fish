function iterm_tab_colors
    switch $argv[1]
        case green
            echo -e "\033]6;1;bg;red;brightness;57\a"
            echo -e "\033]6;1;bg;green;brightness;197\a"
            echo -e "\033]6;1;bg;blue;brightness;77\a"
        case red
            echo -e "\033]6;1;bg;red;brightness;270\a"
            echo -e "\033]6;1;bg;green;brightness;60\a"
            echo -e "\033]6;1;bg;blue;brightness;83\a"
        case blue
            echo -e "\033]6;1;bg;red;brightness;83\a"
            echo -e "\033]6;1;bg;green;brightness;60\a"
            echo -e "\033]6;1;bg;blue;brightness;270\a"
        case orange
            echo -e "\033]6;1;bg;red;brightness;227\a"
            echo -e "\033]6;1;bg;green;brightness;143\a"
            echo -e "\033]6;1;bg;blue;brightness;10\a"
        case reset
            echo -e "\033]6;1;bg;*;default\a"
    end
end

