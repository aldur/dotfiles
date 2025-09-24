local M = {}

local function join_path(args) return table.concat(args, "/") end

-- Running `pipenv` in a subshell is expensive, so we cache the result.
-- Reset it w/ `lua require('aldur.python').venv_cache = {}`
M.venv_cache = {}

function M.find_python_venv(workspace_rootdir)
    -- Use activated virtualenv.
    if vim.env.VIRTUAL_ENV then return vim.env.VIRTUAL_ENV end

    -- Try looking in cache.
    if M.venv_cache[workspace_rootdir] then
        return M.venv_cache[workspace_rootdir]
    end

    if not workspace_rootdir then return nil end

    local local_venv = join_path({workspace_rootdir, '.venv'})
    -- NOTE: Remember that in `lua` anything not false or nil is true!
    if vim.fn.isdirectory(local_venv) == 1 and
        vim.fn.executable(join_path({local_venv, "bin", "python"})) == 1 then
        local msg = "Found local virtualenv at " .. local_venv
        _G.info_message(msg)

        M.venv_cache[workspace_rootdir] = local_venv
        return local_venv
    end

    -- Find and use virtualenv from pipenv in workspace directory.
    local match = vim.fn.glob(join_path({workspace_rootdir, 'Pipfile'}))
    if match ~= '' and vim.fn.executable('pipenv') == 1 then
        local venv_cmd = vim.system({"pipenv", "-q", "--venv"}, {
            text = true,
            env = {PIPENV_PIPFILE = match}
        }):wait()

        if venv_cmd.code == 0 then
            local venv = vim.fn.trim(venv_cmd.stdout)

            local msg = "Activating Pipenv at " .. venv
            _G.info_message(msg)

            M.venv_cache[workspace_rootdir] = venv

            return venv
        end
    end

    match = vim.fn.glob(join_path({workspace_rootdir, 'poetry.lock'}))
    if match ~= '' and vim.fn.executable('poetry') == 1 then
        local venv_cmd = vim.system({
            'poetry', 'env', 'info', '-p', '-C', workspace_rootdir
        }, {text = true}):wait()

        if venv_cmd.code == 0 then
            local venv = vim.fn.trim(venv_cmd.stdout)
            local msg = "Activating poetry venv at " .. venv
            _G.info_message(msg)

            M.venv_cache[workspace_rootdir] = venv

            return venv
        end
    end

    return nil
end

-- Running `pipenv` in a subshell is expensive, so we cache the result.
-- Reset it w/ `lua require('aldur/python').venv_cache = {}`
M.direnv_cache = {}

function M.try_python_direnv(workspace_rootdir)
    if M.direnv_cache[workspace_rootdir] then
        return M.direnv_cache[workspace_rootdir]
    end

    local direnv_cmd = vim.system({
        "direnv", "exec", workspace_rootdir, "which", "python"
    }, {text = true}):wait()

    if direnv_cmd.code == 0 then
        local python = vim.fn.trim(direnv_cmd.stdout)
        local msg = "Using direnv Python at " .. python
        _G.info_message(msg)

        M.direnv_cache[workspace_rootdir] = python

        return python
    end

    return nil
end

-- https://github.com/neovim/nvim-lspconfig/issues/500#issuecomment-876700701
function M.find_python_path(workspace_rootdir)
    -- NOTE: 2025-03-19 venv support temporarily disabled due to false positives.
    local venv = M.find_python_venv(workspace_rootdir)
    if venv then return join_path({venv, 'bin', 'python'}) end

    local direnv = M.try_python_direnv(workspace_rootdir)
    if direnv then return direnv end

    -- Fallback to system Python.
    return vim.fn.exepath('python3') or vim.fn.exepath('python') or 'python'
end

function M.executable_path(workspace_rootdir, executable)
    local venv = M.find_python_venv(workspace_rootdir)
    if venv then return join_path({venv, 'bin', executable}) end

    -- Fallback to system.
    -- TODO: Fail if not found?
    return vim.fn.exepath(executable) or executable
end

return M
