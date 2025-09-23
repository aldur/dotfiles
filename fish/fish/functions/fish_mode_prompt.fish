function fish_mode_prompt
  switch $fish_bind_mode
    case default
      set_color --bold green
      echo 'NRM '
    case insert
      set_color --bold '#c6e2ff'
      echo 'INS '
    case replace_one
      set_color --bold red
      echo 'RPL '
    case visual
      set_color --bold orange
      echo 'VSL '
    case '*'
      set_color --bold red
      echo '? '
  end

  set_color normal
end
