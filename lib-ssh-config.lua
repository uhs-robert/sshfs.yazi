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

--- Resolve the full SSH config for a hostname via `ssh -G`.
--- Returns a table of key/value pairs (HostName, User, Port, etc.)
--- This correctly handles Include, Match, ProxyJump, and HostName aliases.
---@param hostname string
---@return table<string, string>
function SSHCONFIG.resolve(hostname)
  local child, spawn_err = Command("ssh"):arg({ "-G", hostname }):stdout(Command.PIPED):stderr(Command.PIPED):spawn()
  if not child then
    local Notify = require(".lib-notify")
    Notify.debug("ssh -G failed for %s: %s", hostname, tostring(spawn_err))
    return {}
  end
  local output = child:wait_with_output()
  if not output or not output.status.success then
    local Notify = require(".lib-notify")
    Notify.debug("ssh -G failed for %s", hostname)
    return {}
  end

  local result = {}
  for line in output.stdout:gmatch("[^\r\n]+") do
    local key, value = line:match("^(%S+)%s+(.+)$")
    if key then result[key:lower()] = value end
  end
  return result
end

return SSHCONFIG
