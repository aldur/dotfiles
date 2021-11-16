function pv-folder
    pv -s (du -sb $argv | awk '{print $1}')
end
