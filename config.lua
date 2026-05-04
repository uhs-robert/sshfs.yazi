-- config.lua
local CONFIG = {}

local HOME = os.getenv("HOME")
local XDG_DATA_HOME = os.getenv("XDG_DATA_HOME") or (HOME .. "/.local/share")
local State = require(".lib-state")

CONFIG.defaults = {
  enable_debug = false,
  debug_log_file = nil, -- e.g. "/tmp/sshfs-debug.log" for tail -f style output
  custom_hosts_file = XDG_DATA_HOME .. "/yazi/sshfs.list", -- list of remembered aliases
  mount_dir = HOME .. "/mnt",
  default_mount_point = "auto", -- "auto" (prompt), "home", or "root"
  default_user = "auto", -- "auto" (use SSH config user) or "prompt" (ask user)
  sshfs_options = {
    "reconnect",
    "ConnectTimeout=5",
    "compression=yes",
    "ServerAliveInterval=15",
    "ServerAliveCountMax=3",
  },
  connections = {
    control_persist = "10m", -- how long the ControlMaster socket stays alive after last use
    socket_dir = HOME .. "/.ssh/sockets", -- where ControlMaster sockets are stored
  },
  global_paths = {}, -- remote paths offered for all hosts, e.g. { "/", "/var/log" }
  host_paths = {}, -- per-host paths, e.g. { myserver = "/src/www" }
  on_mount = {
    auto_jump = true, -- jump to the mount directory after a successful mount
  },
  on_exit = {
    clean_mount_folders = true, -- delete empty mount directories after unmounting
  },
  ui = {
    menu_max = 15, -- max items before switching from which-key menu to fzf/filter (max 36)
    picker = "auto", -- "auto", "fzf", or "menu"
  },
}

--- Deep-merge two tables. Values in `overrides` take precedence.
---@param defaults table
---@param overrides table|nil
---@return table
function CONFIG.deep_merge(defaults, overrides)
  if type(overrides) ~= "table" then return defaults end
  local result = {}
  for k, v in pairs(defaults) do
    if type(v) == "table" and type(overrides[k]) == "table" then
      result[k] = CONFIG.deep_merge(v, overrides[k])
    else
      result[k] = overrides[k] ~= nil and overrides[k] or v
    end
  end
  for k, v in pairs(overrides) do
    if result[k] == nil then result[k] = v end
  end
  return result
end

--- Merge user-provided options into the defaults and persist to plugin state.
---@param user_config table|nil
function CONFIG.setup(user_config)
  local config = CONFIG.deep_merge(CONFIG.defaults, user_config or {})
  State.set(State.KEY.CONFIG, config)
end

--- Retrieve the active plugin configuration from state.
---@return table
function CONFIG.get()
  return State.get(State.KEY.CONFIG)
end

return CONFIG
