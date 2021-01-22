# Fix slow completion on Big Sur
# https://github.com/fish-shell/fish-shell/issues/6270#issuecomment-570778482

if test (uname) = Darwin
    function __fish_describe_command; end
    exit
end

