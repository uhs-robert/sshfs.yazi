-- lib-hosts.lua

local Notify = require(".lib-notify")

local HOSTS = {}

--- Module-level host cache. Invalidated when SSH config or hosts file changes.
local CACHE = {
  hosts = nil,
  ssh_config_mtime = 0,
  save_file_mtime = 0,
}

--- Combine two lists.
---@param a string[]
---@param b string[]
---@return string[]
local function list_extend(a, b)
  local result = {}
  for _, v in ipairs(a) do
    result[#result + 1] = v
  end
  for _, v in ipairs(b) do
    result[#result + 1] = v
  end
  return result
end

--- Remove duplicate values, preserving order.
---@param list string[]
---@return string[]
local function unique(list)
  local seen, out = {}, {}
  for _, v in ipairs(list) do
    if not seen[v] then
      seen[v] = true
      out[#out + 1] = v
    end
  end
  return out
end

---@param hosts_file string
---@return boolean
local function is_cache_valid(hosts_file)
  local Fs = require(".lib-fileservice")
  local SshConfig = require(".lib-ssh-config")
  return CACHE.hosts ~= nil
    and CACHE.ssh_config_mtime == SshConfig.mtime()
    and CACHE.save_file_mtime == Fs.get_mtime(hosts_file)
end

---@param hosts string[]
---@param hosts_file string
local function update_cache(hosts, hosts_file)
  local Fs = require(".lib-fileservice")
  local SshConfig = require(".lib-ssh-config")
  CACHE.hosts = hosts
  CACHE.ssh_config_mtime = SshConfig.mtime()
  CACHE.save_file_mtime = Fs.get_mtime(hosts_file)
end

--- Force the host list to be re-read on the next call to get_all().
function HOSTS.invalidate()
  CACHE.hosts = nil
end

--- Return all available hosts: custom saved aliases + SSH config hosts.
---@param hosts_file string
---@return string[]
function HOSTS.get_all(hosts_file)
  if is_cache_valid(hosts_file) then return CACHE.hosts end

  local SshConfig = require(".lib-ssh-config")
  local ssh_hosts = SshConfig.list_hosts()
  local hosts

  local cha, _ = fs.cha(Url(hosts_file))
  if cha then
    local State = require(".lib-state")
    local saved = State.read_lines(hosts_file)
    hosts = unique(list_extend(saved, ssh_hosts))
  else
    hosts = ssh_hosts
  end

  update_cache(hosts, hosts_file)
  return hosts
end

--- Parse a host entry that may contain a remote path suffix.
--- Supported forms: "host", "host:/path", "user@host:/path", "host:port:/path"
---@param entry string
---@return string hostname, string|nil remote_path
function HOSTS.parse_entry(entry)
  local parts = {}
  for part in entry:gmatch("[^:]+") do
    parts[#parts + 1] = part
  end

  if #parts == 1 then
    return entry, nil
  elseif #parts == 2 then
    -- "host:/path" vs "host:port"
    return parts[2]:sub(1, 1) == "/" and parts[1] or entry, parts[2]:sub(1, 1) == "/" and parts[2] or nil
  elseif #parts >= 3 then
    -- Last segment is a path if it starts with /
    if parts[#parts]:sub(1, 1) == "/" then return table.concat(parts, ":", 1, #parts - 1), parts[#parts] end
    return entry, nil
  end

  return entry, nil
end

--- Generate a short mount-point suffix from a remote path.
--- Takes the last two path components to keep directory names readable.
---@param remote_path string e.g. "/var/lib/docker/volumes"
---@return string e.g. "docker-volumes"
function HOSTS.mount_suffix(remote_path)
  if not remote_path or remote_path == "" then return "" end
  remote_path = remote_path:gsub("/+$", "")
  if remote_path == "/" or remote_path == "" then return "root" end

  local components = {}
  for c in remote_path:gmatch("[^/]+") do
    components[#components + 1] = c
  end

  local count = math.min(2, #components)
  local parts = {}
  for i = #components - count + 1, #components do
    parts[#parts + 1] = components[i]
  end

  local suffix = table.concat(parts, "-"):gsub("[^%w%-_]", "-"):gsub("%-+", "-")
  return suffix
end

return HOSTS
