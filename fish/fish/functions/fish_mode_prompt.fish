function fish_mode_prompt
  switch $fish_bind_mode
    case default
      set_color --bold green
      echo 'NORMAL '
    case insert
      set_color --bold '#c6e2ff'
      echo 'INSERT '
    case replace_one
      set_color --bold red
      echo 'REPLACE '
    case visual
      set_color --bold orange
      echo 'VISUAL '
    case '*'
      set_color --bold red
      echo '? '
  end

  set_color normal
end
