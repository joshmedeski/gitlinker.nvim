local logger = require("gitlinker.logger")
local spawn = require("gitlinker.spawn")

--- @class JobResult
--- @field stdout string[]
--- @field stderr string[]
local JobResult = {}

--- @return JobResult
function JobResult:new()
    local o = {
        stdout = {},
        stderr = {},
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

--- @return boolean
function JobResult:has_out()
    return type(self.stdout) == "table" and #self.stdout > 0
end

--- @return boolean
function JobResult:has_err()
    return type(self.stderr) == "table" and #self.stderr > 0
end

--- @param default string
function JobResult:print_err(default)
    if self:has_err() then
        for _, e in ipairs(self.stderr) do
            logger.err("%s", e)
        end
    else
        logger.err("fatal: %s", default)
    end
end

-- wrap the git command to do the right thing always
--- @package
--- @param args string[]
--- @param cwd string|nil
--- @return JobResult
local function cmd(args, cwd)
    local result = JobResult:new()

    local sp = spawn.Spawn:make(args, function(line)
        if type(line) == "string" then
            table.insert(result.stdout, line)
        end
    end, function(line)
        if type(line) == "string" then
            table.insert(result.stderr, line)
        end
    end) --[[@as Spawn]]
    sp:run()

    logger.debug(
        "|cmd| args(%s):%s, cwd(%s):%s, result(%s):%s",
        vim.inspect(type(args)),
        vim.inspect(args),
        vim.inspect(type(cwd)),
        vim.inspect(cwd),
        vim.inspect(type(result)),
        vim.inspect(result)
    )
    return result
end

--- @package
--- @return JobResult
local function get_remote()
    local result = cmd({ "git", "remote" })
    logger.debug(
        "|git.get_remote| result(%s):%s",
        vim.inspect(type(result)),
        vim.inspect(result)
    )
    return result
end

--- @param remote string
--- @return JobResult
local function get_remote_url(remote)
    assert(remote, "remote cannot be nil")
    local result = cmd({ "git", "remote", "get-url", remote })
    logger.debug(
        "|git.get_remote_url| remote(%s):%s, result(%s):%s",
        vim.inspect(type(remote)),
        vim.inspect(remote),
        vim.inspect(type(result)),
        vim.inspect(result)
    )
    return result
end

--- @package
--- @param revspec string|nil
--- @return string?
local function get_rev(revspec)
    local result = cmd({ "git", "rev-parse", revspec })
    logger.debug(
        "|git.get_rev| revspec(%s):%s, result(%s):%s",
        vim.inspect(type(revspec)),
        vim.inspect(revspec),
        vim.inspect(type(result)),
        vim.inspect(result)
    )
    return result:has_out() and result.stdout[1] or nil
end

--- @package
--- @param revspec string
--- @return JobResult
local function get_rev_name(revspec)
    local result = cmd({ "git", "rev-parse", "--abbrev-ref", revspec })
    logger.debug(
        "|git.get_rev_name| revspec(%s):%s, result(%s):%s",
        vim.inspect(type(revspec)),
        vim.inspect(revspec),
        vim.inspect(type(result)),
        vim.inspect(result)
    )
    return result
end

--- @param file string
--- @param revspec string
--- @return JobResult
local function is_file_in_rev(file, revspec)
    local result = cmd({ "git", "cat-file", "-e", revspec .. ":" .. file })
    logger.debug(
        "|git.is_file_in_rev| file(%s):%s, revspec(%s):%s, result(%s):%s",
        vim.inspect(type(file)),
        vim.inspect(file),
        vim.inspect(type(revspec)),
        vim.inspect(revspec),
        vim.inspect(type(result)),
        vim.inspect(result)
    )
    return result
end

--- @param file string
--- @param rev string
--- @return boolean
local function has_file_changed(file, rev)
    local result = cmd({ "git", "diff", rev, "--", file })
    logger.debug(
        "|git.has_file_changed| file(%s):%s, rev(%s):%s, result(%s):%s",
        vim.inspect(type(file)),
        vim.inspect(file),
        vim.inspect(type(rev)),
        vim.inspect(rev),
        vim.inspect(type(result)),
        vim.inspect(result)
    )
    return result:has_out()
end

--- @package
--- @param revspec string
--- @param remote string
--- @return boolean
local function is_rev_in_remote(revspec, remote)
    local result = cmd({ "git", "branch", "--remotes", "--contains", revspec })
    logger.debug(
        "|git.is_rev_in_remote| revspec(%s):%s, remote(%s):%s, result(%s):%s",
        vim.inspect(type(revspec)),
        vim.inspect(revspec),
        vim.inspect(type(remote)),
        vim.inspect(remote),
        vim.inspect(type(result)),
        vim.inspect(result)
    )
    local output = result.stdout
    for _, rbranch in ipairs(output) do
        if rbranch:match(remote) then
            return true
        end
    end
    return false
end

local UpstreamBranchAllowedChars = "[_%-%w%.]+"

--- @param remote string
--- @return string|nil
local function get_closest_remote_compatible_rev(remote)
    assert(remote, "remote cannot be nil")

    -- try upstream branch HEAD (a.k.a @{u})
    local upstream_rev = get_rev("@{u}")
    if upstream_rev then
        return upstream_rev
    end

    -- try HEAD
    if is_rev_in_remote("HEAD", remote) then
        local head_rev = get_rev("HEAD")
        if head_rev then
            return head_rev
        end
    end

    -- try last 50 parent commits
    for i = 1, 50 do
        local revspec = "HEAD~" .. i
        if is_rev_in_remote(revspec, remote) then
            local rev = get_rev(revspec)
            if rev then
                return rev
            end
        end
    end

    -- try remote HEAD
    local remote_rev = get_rev(remote)
    if remote_rev then
        return remote_rev
    end

    logger.err(
        "fatal: failed to get closest revision in that exists in remote '%s'",
        remote
    )
    return nil
end

--- @return JobResult
local function get_root()
    local buf_path = vim.api.nvim_buf_get_name(0)
    local buf_dir = vim.fn.fnamemodify(buf_path, ":p:h")
    local result = cmd({ "git", "rev-parse", "--show-toplevel" }, buf_dir)
    logger.debug(
        "|git.get_root| buf_path(%s):%s, buf_dir(%s):%s, result(%s):%s",
        vim.inspect(type(buf_path)),
        vim.inspect(buf_path),
        vim.inspect(type(buf_dir)),
        vim.inspect(buf_dir),
        vim.inspect(type(result)),
        vim.inspect(result)
    )
    return result
end

--- @return string?
local function get_branch_remote()
    -- origin/upstream
    --- @type JobResult
    local remote_result = get_remote()

    if type(remote_result.stdout) ~= "table" or #remote_result.stdout == 0 then
        remote_result:print_err("git repository has no remote")
        return nil
    end

    if #remote_result.stdout == 1 then
        return remote_result.stdout[1]
    end

    -- origin/linrongbin16/add-rule2
    --- @type JobResult
    local upstream_branch_result = get_rev_name("@{u}")
    if not upstream_branch_result:has_out() then
        upstream_branch_result:print_err("git branch has no remote")
        return nil
    end

    --- @type string
    local upstream_branch = upstream_branch_result.stdout[1]
    -- origin
    --- @type string
    local remote_from_upstream_branch =
        upstream_branch:match("^(" .. UpstreamBranchAllowedChars .. ")%/")

    if not remote_from_upstream_branch then
        logger.err(
            "fatal: cannot parse remote name from remote branch '%s'",
            upstream_branch
        )
        return nil
    end

    local remotes = remote_result.stdout
    for _, remote in ipairs(remotes) do
        if remote_from_upstream_branch == remote then
            return remote
        end
    end

    logger.err(
        "fatal: parsed remote '%s' from remote branch '%s' is not a valid remote",
        remote_from_upstream_branch,
        upstream_branch
    )
    return nil
end

local M = {
    get_root = get_root,
    get_remote_url = get_remote_url,
    is_file_in_rev = is_file_in_rev,
    has_file_changed = has_file_changed,
    get_closest_remote_compatible_rev = get_closest_remote_compatible_rev,
    get_branch_remote = get_branch_remote,
}

return M
