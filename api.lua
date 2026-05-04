-- api.lua
local Notify = require(".lib-notify")
local API = {}

local HOME = os.getenv("HOME")

--- Build display labels for a list of mounts (includes remote info when known).
---@param mounts { alias: string, path: string, remote: string|nil }[]
---@return string[]
local function mount_labels(mounts)
  local labels = {}
  for _, m in ipairs(mounts) do
    labels[#labels + 1] = m.remote and (m.remote .. " → " .. m.alias) or m.alias
  end
  return labels
end

--- Find a mount by matching it to a label string.
---@param labels string[]
---@param choice string
---@param mounts table[]
---@return table|nil
local function find_by_label(labels, choice, mounts)
  for i, label in ipairs(labels) do
    if label == choice then return mounts[i] end
  end
  return nil
end

--- Return active mounts, or warn and return nil if there are none.
---@param warn_msg string|nil
---@return table[]|nil
local function active_mounts_or_warn(warn_msg)
  local Mount = require(".lib-mount")
  local State = require(".lib-state")
  local config = State.get(State.KEY.CONFIG)
  local mounts = Mount.list(config.mount_dir)
  if #mounts == 0 then
    if warn_msg then Notify.warn(warn_msg) end
    return nil
  end
  return mounts
end

--- Check if an alias already exists in the custom hosts file.
---@param alias string
---@param hosts_file string
---@return boolean
local function alias_exists(alias, hosts_file)
  local State = require(".lib-state")
  for _, line in ipairs(State.read_lines(hosts_file)) do
    if line == alias then return true end
  end
  return false
end

--- Add a custom SSH host alias to the saved hosts file.
function API.add()
  local Prompt = require(".ui-prompt")
  local State = require(".lib-state")
  local config = State.get(State.KEY.CONFIG)

  local host = Prompt.input("Enter SSH host:")
  if not host then return end
  if not host:match("^[%w_.%-@]+:?[%w%-%.]*$") then
    Notify.error("Invalid SSH host string")
    return
  end
  if alias_exists(host, config.custom_hosts_file) then
    Notify.warn("Host already exists")
    return
  end

  local remote_dir = Prompt.input("Remote directory (optional, leave blank for ~):")
  if remote_dir == nil then return end

  local alias = host
  if remote_dir ~= "" then
    if not remote_dir:match("^/") then
      Notify.error("Remote directory must be an absolute path starting with /")
      return
    end
    alias = host .. ":" .. remote_dir
  end

  if alias_exists(alias, config.custom_hosts_file) then
    Notify.warn("Host alias already exists")
    return
  end

  State.append_line(config.custom_hosts_file, alias)
  local Hosts = require(".lib-hosts")
  Hosts.invalidate()
  Notify.info("Added %s to custom hosts", alias)
end

--- Remove a custom SSH host alias from the saved hosts file.
function API.remove()
  local State = require(".lib-state")
  local config = State.get(State.KEY.CONFIG)
  local url = Url(config.custom_hosts_file)
  if not fs.cha(url) then
    Notify.warn("No custom hosts to remove")
    return
  end

  local saved = State.read_lines(config.custom_hosts_file)

  local Picker = require(".ui-picker")
  local alias = Picker.choose("Remove which?", saved, config)
  if not alias then return end

  local updated = {}
  for _, line in ipairs(saved) do
    if line ~= alias then updated[#updated + 1] = line end
  end

  if #updated == 0 then
    fs.remove("file", url)
  else
    local f, err = io.open(config.custom_hosts_file, "w")
    if not f then
      Notify.error("Failed to open hosts file: %s", tostring(err))
      return
    end
    for _, line in ipairs(updated) do
      f:write(line, "\n")
    end
    f:close()
  end

  local Hosts = require(".lib-hosts")
  Hosts.invalidate()
  Notify.info('Removed "%s" from custom hosts', alias)
end

--- Mount a remote host.
---@param args table job args (args.jump overrides on_mount.auto_jump)
function API.mount(args)
  local State = require(".lib-state")
  local Picker = require(".ui-picker")
  local Hosts = require(".lib-hosts")
  local Sshfs = require(".lib-sshfs")
  local config = State.get(State.KEY.CONFIG)
  local hosts = Hosts.get_all(config.custom_hosts_file)

  local chosen = (#hosts == 1) and hosts[1] or Picker.choose("Mount which host?", hosts, config)
  if chosen then Sshfs.mount(chosen, { jump = args and args.jump or nil }) end
end

--- Jump to an active mount point.
function API.jump()
  local mounts = active_mounts_or_warn("No active mounts to jump to")
  if not mounts then return end

  local State = require(".lib-state")
  local config = State.get(State.KEY.CONFIG)
  local labels = mount_labels(mounts)
  local Picker = require(".ui-picker")
  local choice = Picker.choose("Jump to mount", labels, config)
  if not choice then return end

  local mount = find_by_label(labels, choice, mounts)
  if mount then ya.emit("cd", { mount.path, raw = true }) end
end

--- Unmount an active mount point.
function API.unmount()
  local mounts = active_mounts_or_warn("No SSHFS mounts are active")
  if not mounts then return end

  local State = require(".lib-state")
  local config = State.get(State.KEY.CONFIG)
  local labels = mount_labels(mounts)
  local Picker = require(".ui-picker")
  local choice = Picker.choose("Unmount which?", labels, config)
  if not choice then return end

  local mount = find_by_label(labels, choice, mounts)
  if not mount then
    Notify.error("Internal error: mount not found")
    return
  end

  State.redirect_tabs_to_home(mount.path)
  local clean = config.on_exit and config.on_exit.clean_mount_folders
  local Mount = require(".lib-mount")
  if Mount.remove(mount.path, clean) then
    local hostname = mount.alias:match("^([^%-]+)") or mount.alias
    local Ssh = require(".lib-ssh")
    local Lockfile = require(".lib-lockfile")
    Ssh.close_socket(hostname, config)
    Lockfile.release(mount.alias)
    Notify.info("Unmounted %s", mount.alias)
  else
    Notify.error("Failed to unmount %s", mount.alias)
  end
end

--- Open an interactive SSH terminal to a mounted host.
function API.terminal()
  local mounts = active_mounts_or_warn("No active mounts")
  if not mounts then return end

  local State = require(".lib-state")
  local config = State.get(State.KEY.CONFIG)
  local labels = mount_labels(mounts)
  local Picker = require(".ui-picker")
  local choice = Picker.choose("Open terminal to:", labels, config)
  if not choice then return end

  local mount = find_by_label(labels, choice, mounts)
  if not mount then return end

  local hostname = mount.alias:match("^([^%-]+)") or mount.alias
  local ssh_args = { "ssh" }

  local Ssh = require(".lib-ssh")
  if Ssh.socket_alive(hostname, config) then
    local sock = Ssh.socket_path(hostname, config)
    ssh_args[#ssh_args + 1] = "-o"
    ssh_args[#ssh_args + 1] = "ControlPath=" .. sock
    ssh_args[#ssh_args + 1] = "-o"
    ssh_args[#ssh_args + 1] = "ControlMaster=no"
  end

  ssh_args[#ssh_args + 1] = hostname
  ya.emit("shell", { table.concat(ssh_args, " "), block = true })
end

--- Navigate to the mount base directory.
function API.home()
  local State = require(".lib-state")
  local config = State.get(State.KEY.CONFIG)
  ya.emit("cd", { config.mount_dir, raw = true })
end

--- Navigate to the directory containing the custom hosts file.
function API.hosts()
  local State = require(".lib-state")
  local config = State.get(State.KEY.CONFIG)
  local parent = config.custom_hosts_file:match("^(.+)/[^/]+$")
  ya.emit("cd", { parent, raw = true })
end

--- Navigate to the ~/.ssh/ directory.
function API.ssh_config()
  ya.emit("cd", { HOME .. "/.ssh/", raw = true })
end

--- Show the interactive top-level menu.
function API.menu()
  local choice = ya.which({
    title = "SSHFS",
    cands = {
      { on = "m", desc = "Mount" },
      { on = "u", desc = "Unmount" },
      { on = "t", desc = "Terminal" },
      { on = "a", desc = "Add host" },
      { on = "r", desc = "Remove host" },
      { on = "h", desc = "Go to mount home" },
      { on = "c", desc = "Open ~/.ssh/" },
      { on = "l", desc = "Open custom host list" },
    },
  })

  local dispatch = {
    [1] = function()
      API.mount({})
    end,
    [2] = API.unmount,
    [3] = API.terminal,
    [4] = API.add,
    [5] = API.remove,
    [6] = API.home,
    [7] = API.ssh_config,
    [8] = API.hosts,
  }

  if choice and dispatch[choice] then dispatch[choice]() end
end

return API
