-- lib-ssh-config.lua

local SSHCONFIG = {}

local HOME = os.getenv("HOME")
local SSH_CONFIG = HOME .. "/.ssh/config"

SSHCONFIG.PATH = SSH_CONFIG

--- Return the mtime of the SSH config file (used for cache invalidation).
---@return integer
function SSHCONFIG.mtime()
  local Fs = require(".lib-fileservice")
  return Fs.get_mtime(SSH_CONFIG)
end

--- Parse Host entries from the SSH config file.
--- Wildcards and negations are excluded.
--- Include directives are not followed; use ssh -G for full resolution.
---@return string[]
function SSHCONFIG.list_hosts()
  local list = {}
  local f = io.open(SSH_CONFIG)
  if not f then return list end
  for line in f:lines() do
    local host = line:match("^%s*Host%s+([^%s]+)")
    if host and not host:find("[*?!]") then list[#list + 1] = host end
  end
  f:close()
  return list
end

return SSHCONFIG
