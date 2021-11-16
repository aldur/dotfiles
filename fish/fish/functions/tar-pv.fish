function tar-pv
    tar -cz $argv | pv -s (du -sb $argv | awk '{print $1}')
end
