-- lib-sshfs.lua

local SSHFS = {}

--- Build the remote path string passed to sshfs (e.g. "alias:/var/log").
---@param alias string
---@param mount_to_root boolean
---@param custom_remote_path string|nil
---@return string
local function remote_spec(alias, mount_to_root, custom_remote_path)
  if custom_remote_path then return alias .. ":" .. custom_remote_path end
  return alias .. ":" .. (mount_to_root and "/" or "")
end

--- Assemble sshfs -o options for the given socket path and config.
---@param config table
---@param socket_path string|nil
---@return string[]
local function sshfs_options(config, socket_path)
  local opts = { "BatchMode=yes" }
  if socket_path then
    opts[#opts + 1] = "ControlPath=" .. socket_path
    opts[#opts + 1] = "ControlMaster=no"
  end
  if config.sshfs_options then
    for _, o in ipairs(config.sshfs_options) do
      opts[#opts + 1] = o
    end
  end
  return opts
end

--- Try to mount using SSH key authentication (non-interactive).
---@param alias string
---@param mount_point string
---@param mount_to_root boolean
---@param remote_path string|nil
---@param config table
---@param socket_path string|nil
---@return string|nil err, Output|nil output
local function try_key_auth(alias, mount_point, mount_to_root, remote_path, config, socket_path)
  local opts = sshfs_options(config, socket_path)
  local args = { remote_spec(alias, mount_to_root, remote_path), mount_point, "-o", table.concat(opts, ",") }
  local child, spawn_err = Command("sshfs"):arg(args):stdout(Command.PIPED):stderr(Command.PIPED):spawn()
  if not child then return tostring(spawn_err), nil end
  local output, out_err = child:wait_with_output()
  if not output then return tostring(out_err), nil end
  if output.status and output.status.success then return nil, output end
  return output.stderr ~= "" and output.stderr or "sshfs failed", output
end

--- Check whether `hostname` already has an active mount under mount_dir.
---@param hostname string
---@param mount_dir string
---@return string|nil mount_path
local function find_existing_mount(hostname, mount_dir)
  local Mount = require(".lib-mount")
  for _, m in ipairs(Mount.list(mount_dir)) do
    if (m.alias:match("^([^%-]+)") or m.alias) == hostname then return m.path end
  end
  return nil
end

--- Normalize a user-typed remote path.
--- Empty/blank → "/", "~"/"~/…" pass through, no leading "/" → prepend "/".
---@param path string|nil
---@return string
local function normalize_remote_path(path)
  if not path or path:match("^%s*$") then return "/" end
  path = path:match("^%s*(.-)%s*$")
  if path == "~" then return "/" end -- sshfs doesn't expand ~, default dir resolves relative to home
  if path:match("^~/") then return path:sub(3) end
  if path:sub(1, 1) ~= "/" then return "/" .. path end
  return path
end

--- Called after a successful mount. Notifies the user and optionally jumps.
---@param entry string display name (the original host entry)
---@param mount_point string
---@param config table
---@param jump_override boolean|nil explicit override; nil defers to config
local function finalize(entry, mount_point, config, jump_override)
  local Notify = require(".lib-notify")
  Notify.info("Mounted %s", entry)
  local do_jump = jump_override ~= nil and jump_override
    or (config.on_mount == nil or config.on_mount.auto_jump ~= false)
  if do_jump then ya.emit("cd", { mount_point, raw = true }) end
end

--- Mount a host entry, handling user selection, auth, and post-mount actions.
---@param entry string host entry, optionally with remote path e.g. "host:/var/log"
---@param opts? { jump: boolean|nil } override options
function SSHFS.mount(entry, opts)
  local Notify = require(".lib-notify")
  local Fs = require(".lib-fileservice")
  local Hosts = require(".lib-hosts")
  local State = require(".lib-state")
  opts = opts or {}
  local config = State.get(State.KEY.CONFIG)
  local mount_dir = config.mount_dir
  Fs.ensure_dir(Url(mount_dir))

  local hostname, remote_path = Hosts.parse_entry(entry)
  Notify.debug("Mounting: hostname=%s remote_path=%s", hostname, remote_path or "nil")

  local existing = find_existing_mount(hostname, mount_dir)
  if existing then
    Notify.warn("Host %s already mounted at %s — unmount it first", hostname, existing)
    return
  end

  -- Prompt for user if configured
  local prompt = require(".ui-prompt")
  local alias = prompt.choose_user(hostname, config)
  if not alias then return end

  local Ssh = require(".lib-ssh")
  if not Ssh.ensure_socket(alias, config) then
    if not Ssh.open_auth_terminal(alias, config) then
      Notify.warn("Authentication cancelled")
      return
    end
  end
  local sock_path = Ssh.socket_path(alias, config)

  -- Determine remote path if not already set from the entry
  local mount_to_root = false
  if not remote_path then
    local map = { root = true, home = false }
    mount_to_root = map[config.default_mount_point]
    if mount_to_root == nil then
      local CUSTOM = "Custom path\xe2\x80\xa6"
      local options = { "~ (home)", "/ (root)", CUSTOM }

      if config.host_paths and config.host_paths[hostname] then
        local hp = config.host_paths[hostname]
        if type(hp) == "string" then
          options[#options + 1] = hp
        else
          for _, p in ipairs(hp) do
            options[#options + 1] = p
          end
        end
      end

      if config.global_paths then
        for _, p in ipairs(config.global_paths) do
          options[#options + 1] = p
        end
      end

      local picker = require(".ui-picker")
      local chosen = picker.choose("Mount where?", options, config)
      if not chosen then return end

      if chosen == "/ (root)" then
        mount_to_root = true
      elseif chosen == CUSTOM then
        local typed = prompt.input("Remote path:")
        if not typed then return end
        local normalized = normalize_remote_path(typed)
        if normalized == "/" then
          mount_to_root = true
        else
          remote_path = normalized
        end
      elseif chosen ~= "~ (home)" then
        local normalized = normalize_remote_path(chosen)
        if normalized == "/" then
          mount_to_root = true
        else
          remote_path = normalized
        end
      end
    end
    mount_to_root = mount_to_root or false
  end

  -- Build mount point directory name (remote path now known)
  local mount_point = remote_path and ("%s/%s-%s"):format(mount_dir, hostname, Hosts.mount_suffix(remote_path))
    or ("%s/%s"):format(mount_dir, hostname)

  local mount_url = Url(mount_point)
  Fs.ensure_dir(mount_url)

  local Mount = require(".lib-mount")
  if Mount.is_active(mount_point, mount_url, mount_dir) then
    Notify.info("Already mounted at %s", mount_point)
    return finalize(entry, mount_point, config, opts.jump)
  end

  -- Resolve remote home to handle symlinks / non-standard $HOME
  if not mount_to_root and not remote_path then
    local resolved = Ssh.resolve_home(alias, config)
    if resolved then
      Notify.debug("Resolved remote home: %s", resolved)
      remote_path = resolved
    end
  end

  -- Mount via ControlMaster socket
  local key_err, _ = try_key_auth(alias, mount_point, mount_to_root, remote_path, config, sock_path)
  if not key_err then
    local Lockfile = require(".lib-lockfile")
    Lockfile.acquire(hostname)
    return finalize(entry, mount_point, config, opts.jump)
  end

  if key_err:match("No such file or directory") then
    local display = remote_path or (mount_to_root and "/" or "~")
    Notify.error("Remote directory does not exist: %s:%s", alias, display)
    fs.remove("dir_clean", mount_url)
    return
  end

  if
    key_err:match("Connection refused")
    or key_err:match("Connection timed out")
    or key_err:match("Could not resolve hostname")
  then
    Notify.error("Connection error: %s", key_err)
    fs.remove("dir_clean", mount_url)
    return
  end

  Notify.error("Mount failed: %s", key_err)
  fs.remove("dir_clean", mount_url)
end

return SSHFS
