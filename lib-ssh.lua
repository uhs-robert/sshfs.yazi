-- lib-ssh.lua

local SSH = {}

local HOME = os.getenv("HOME")

---@param path string
---@return string
local function expand_home(path)
  return (path:gsub("^~", HOME or ""))
end

--- Return the configured ControlMaster socket directory.
---@param config table
---@return string
local function socket_dir(config)
  return expand_home((config.connections and config.connections.socket_dir) or (HOME .. "/.ssh/sockets"))
end

--- Return the ControlMaster socket path for a given host alias.
---@param host string e.g. "user@myserver" or "myserver"
---@param config table
---@return string
function SSH.socket_path(host, config)
  local hostname = host:match("@(.+)$") or host
  local name = hostname:gsub("[^%w._%-]", "_")
  return socket_dir(config) .. "/" .. name .. ".socket"
end

--- Return true if the ControlMaster socket for `host` is alive.
---@param host string
---@param config table
---@return boolean
function SSH.socket_alive(host, config)
  local sock = SSH.socket_path(host, config)
  local hostname = host:match("@(.+)$") or host
  local status, err = Command("ssh"):arg({ "-O", "check", "-o", "ControlPath=" .. sock, hostname }):status()
  return err == nil and status ~= nil and status.success
end

--- Ensure a ControlMaster socket exists for `host`, creating one if needed.
--- Uses BatchMode so this only succeeds if key-based auth is available.
--- Returns false silently if key auth is not set up — password auth will be used instead.
---@param host string
---@param config table
---@return boolean
function SSH.ensure_socket(host, config)
  if SSH.socket_alive(host, config) then return true end

  local dir = socket_dir(config)
  fs.create("dir_all", Url(dir))

  local persist = (config.connections and config.connections.control_persist) or "10m"
  local sock = SSH.socket_path(host, config)
  local hostname = host:match("@(.+)$") or host

  local status, err = Command("ssh"):arg({
    "-M",
    "-N",
    "-f",
    "-o",
    "ControlMaster=yes",
    "-o",
    "ControlPath=" .. sock,
    "-o",
    "ControlPersist=" .. persist,
    "-o",
    "BatchMode=yes",
    hostname,
  }):status()

  local ok = err == nil and status.success

  if ok then
    local Notify = require(".lib-notify")
    Notify.debug("ControlMaster socket created: " .. sock)
  end

  return ok
end

--- Open an interactive SSH terminal so the user can authenticate (password, 2FA, host key, etc.).
--- Yazi suspends to the secondary screen; returns once the SSH process exits.
--- Returns true if a live ControlMaster socket exists afterwards.
---@param host string
---@param config table
---@return boolean
function SSH.open_auth_terminal(host, config)
  local dir = socket_dir(config)
  fs.create("dir_all", Url(dir))

  local persist = (config.connections and config.connections.control_persist) or "10m"
  local sock = SSH.socket_path(host, config)

  local hostname = host:match("@(.+)$") or host
  local permit = ui.hide()

  local status, err = Command("ssh")
    :arg({
      "-M",
      "-o",
      "ControlMaster=yes",
      "-o",
      "ControlPath=" .. sock,
      "-o",
      "ControlPersist=" .. persist,
      hostname,
      "exit",
    })
    :stdin(Command.INHERIT)
    :stdout(Command.INHERIT)
    :stderr(Command.INHERIT)
    :status()

  permit:drop()

  if err then
    local Notify = require(".lib-notify")
    Notify.error("SSH auth failed: %s", tostring(err))
    return false
  end

  if not status.success then return false end

  return SSH.socket_alive(host, config)
end

--- Send exit signal to the ControlMaster for `host`, closing the socket.
---@param host string
---@param config table
function SSH.close_socket(host, config)
  if not SSH.socket_alive(host, config) then return end
  local Notify = require(".lib-notify")
  local sock = SSH.socket_path(host, config)
  local hostname = host:match("@(.+)$") or host
  Command("ssh"):arg({ "-O", "exit", "-o", "ControlPath=" .. sock, hostname }):status()
  Notify.debug("ControlMaster socket closed for %s", hostname)
end

--- Resolve the remote home directory via SSH.
--- Handles servers where $HOME is a symlink or non-standard path.
--- Returns nil if the query fails.
---@param host string
---@param config table
---@return string|nil
function SSH.resolve_home(host, config)
  local hostname = host:match("@(.+)$") or host
  local args = {}

  if SSH.socket_alive(host, config) then
    local sock = SSH.socket_path(host, config)
    table.insert(args, "-o")
    table.insert(args, "ControlPath=" .. sock)
    table.insert(args, "-o")
    table.insert(args, "ControlMaster=no")
  end

  table.insert(args, hostname)
  table.insert(args, "readlink -f $HOME 2>/dev/null || echo $HOME")

  local child, _ = Command("ssh"):arg(args):stdout(Command.PIPED):stderr(Command.PIPED):spawn()
  if not child then return nil end
  local output = child:wait_with_output()
  if output and output.status.success then
    local home = output.stdout:match("^(.-)%s*$")
    if home and home ~= "" then return home end
  end
  return nil
end

return SSH
