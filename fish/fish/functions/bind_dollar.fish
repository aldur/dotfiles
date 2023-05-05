function bind_dollar
  switch (commandline -t)
  case "*!"
    commandline -f backward-delete-char history-token-search-backward
  case "*"
    commandline -i '$'
  end
end
