-- lib-mount.lua

local MOUNT = {}

local RESPONSIVE_TIMEOUT_MS = 3000
local READ_EVENT_TIMEOUT = 3 -- event code from Child:read_line_with
-- strerror texts (C locale) that mean the mount lost its connection to the server
local DISCONNECTED_ERRORS = {
  "Transport endpoint is not connected",
  "Input/output error",
  "Software caused connection abort",
}

--- Parse `mount` output for sshfs entries under a given root directory.
---@param mount_output string
---@param root string
---@return { path: string, remote: string }[]
local function parse_mount_output(mount_output, root)
  local mounts = {}
  local root_esc = root:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

  local is_macos = io.popen("uname") ~= nil and io.popen("uname"):read("*l") == "Darwin"
  local pattern = not is_macos and ("^(.+)%son%s(" .. root_esc .. "/.-)%s+type%s+fuse%.sshfs")
    or ("^(.+)%son%s(" .. root_esc .. "/[^%s]+)%s+%(.*[mo][as][cx]fuse")

  for line in mount_output:gmatch("[^\r\n]+") do
    local remote, path = line:match(pattern)
    if path and remote then mounts[#mounts + 1] = { path = path, remote = remote } end
  end
  return mounts
end

--- Try findmnt first (Linux, more reliable), fall back to mount output parsing.
---@param mount_dir string
---@return { path: string, remote: string }[]
local function get_sshfs_mounts(mount_dir)
  local root_pat = "^" .. mount_dir:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "/"

  -- Prefer findmnt on Linux
  local child, _ = Command("findmnt")
    :arg({ "-t", "fuse.sshfs", "-o", "SOURCE,TARGET", "--noheadings", "-l" })
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :spawn()
  if child then
    local output = child:wait_with_output()
    if output and output.status.success then
      local mounts = {}
      for line in output.stdout:gmatch("[^\r\n]+") do
        local remote, path = line:match("^(%S+)%s+(%S+)$")
        if path and remote and path:match(root_pat) then mounts[#mounts + 1] = { path = path, remote = remote } end
      end
      return mounts
    end
  end

  -- Fall back to parsing `mount` output
  local mount_child, _ = Command("mount"):stdout(Command.PIPED):stderr(Command.PIPED):spawn()
  if mount_child then
    local mout = mount_child:wait_with_output()
    if mout then return parse_mount_output(mout.stdout, mount_dir) end
  end

  return {}
end

--- Return true if `path` is an active sshfs mount point.
---@param path string
---@param url Url
---@param mount_dir string
---@return boolean
function MOUNT.is_active(path, url, mount_dir)
  local Fs = require(".lib-fileservice")
  if not Fs.is_dir(url) then return false end
  local mounts = get_sshfs_mounts(mount_dir)
  if #mounts > 0 then
    for _, m in ipairs(mounts) do
      if m.path == path then return true end
    end
    return false
  end
  -- Last resort: non-empty directory implies something is mounted
  return not Fs.is_dir_empty(url)
end

--- Return false only when an active mount is known to have lost its server.
--- After a network drop the mount table still lists the mount, but its requests
--- fail or hang. The probe looks up a random name, which sshfs cannot answer from
--- its listing cache, so only the server can answer. A missing file or a denied
--- permission is still an answer. Only a disconnect error or a timeout counts as
--- dead, so an unclear result never leads to an unmount.
--- A hung FUSE request through `fs.*` blocks the plugin with no way out, so the
--- lookup runs in a child process with a timeout.
---@param path string
---@return boolean
function MOUNT.is_responsive(path)
  local probe_path = ("%s/.sshfs-probe-%d-%d"):format(path, os.time(), math.random(1, 1e9))
  local child = Command("stat"):arg({ "--", probe_path }):env("LC_ALL", "C"):stderr(Command.PIPED):spawn()
  if not child then return true end
  local stderr_line, event = child:read_line_with({ timeout = RESPONSIVE_TIMEOUT_MS })
  local Notify = require(".lib-notify")
  if event == READ_EVENT_TIMEOUT then
    child:start_kill()
    Notify.debug("Probe of %s timed out", path)
    return false
  end
  Notify.debug("Probe of %s: %s", path, stderr_line or "no error")
  for _, error_text in ipairs(DISCONNECTED_ERRORS) do
    if stderr_line and stderr_line:find(error_text, 1, true) then return false end
  end
  return true
end

--- List all active sshfs mounts under mount_dir.
---@param mount_dir string
---@return { alias: string, path: string, remote: string|nil }[]
function MOUNT.list(mount_dir)
  local Notify = require(".lib-notify")
  local mounts = {}
  local parsed = get_sshfs_mounts(mount_dir)

  if #parsed > 0 then
    for _, m in ipairs(parsed) do
      local alias = m.path:match("([^/]+)$")
      if alias then
        Notify.debug("Active mount: %s → %s", m.remote, m.path)
        mounts[#mounts + 1] = { alias = alias, path = m.path, remote = m.remote }
      end
    end
  else
    -- Fallback: scan mount_dir for non-empty directories
    local files, err = fs.read_dir(Url(mount_dir), { resolve = false })
    if not files then
      Notify.debug("Could not read mount_dir: %s", tostring(err))
      return mounts
    end
    for _, file in ipairs(files) do
      local url = file.url
      local path = tostring(url)
      local Fs = require(".lib-fileservice")
      if Fs.is_dir(url) and MOUNT.is_active(path, url, mount_dir) then
        mounts[#mounts + 1] = { alias = file.name, path = path, remote = nil }
      end
    end
  end

  Notify.debug("Found %d active mount(s)", #mounts)
  return mounts
end

--- Unmount a mount point, trying several unmount commands in order.
--- If `clean_dir` is true, removes the (now empty) directory afterwards.
---@param path string
---@param clean_dir? boolean
---@return boolean
function MOUNT.remove(path, clean_dir)
  local attempts = {
    -- 1. Clean
    { "fusermount", { "-u", path } },
    { "fusermount3", { "-u", path } },
    { "umount", { path } },
    { "diskutil", { "unmount", path } },

    -- 2. Lazy
    { "fusermount", { "-uz", path } },
    { "fusermount3", { "-uz", path } },
    { "umount", { "-l", path } },

    -- 3. Force (macOS/Universal)
    { "diskutil", { "unmount", "force", path } },
    { "umount", { "-f", path } },
  }
  for _, cmd in ipairs(attempts) do
    local status, err = Command(cmd[1]):arg(cmd[2]):status()
    if err == nil and status and status.success then
      require(".lib-notify").debug("Unmounted %s with %s %s", path, cmd[1], table.concat(cmd[2], " "))
      if clean_dir then fs.remove("dir_clean", Url(path)) end
      return true
    end
  end
  return false
end

return MOUNT
