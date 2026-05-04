-- lib-lockfile.lua

local LOCKFILE = {}

local USER_ID = ya.uid()
local XDG_RUNTIME_DIR = os.getenv("XDG_RUNTIME_DIR") or ("/run/user/" .. USER_ID)
local LOCK_DIR = XDG_RUNTIME_DIR .. "/sshfs"

---@param mount_name string
---@return string
local function lock_path(mount_name)
  return LOCK_DIR .. "/" .. mount_name:gsub("[^%w._%-]", "_") .. ".lock"
end

--- Acquire a lockfile for the given mount name.
--- Prevents a concurrent Yazi instance from unmounting a shared mount.
---@param mount_name string
---@return boolean
function LOCKFILE.acquire(mount_name)
  fs.create("dir_all", Url(LOCK_DIR))
  local path = lock_path(mount_name)
  local f = io.open(path, "w")
  if not f then
    local Notify = require(".lib-notify")
    Notify.debug("Failed to acquire lockfile for %s", mount_name)
    return false
  end
  f:write(tostring(USER_ID) .. "\n")
  f:close()
  return true
end

--- Release the lockfile for the given mount name.
---@param mount_name string
function LOCKFILE.release(mount_name)
  fs.remove("file", Url(lock_path(mount_name)))
end

--- Return true if a lockfile exists for the given mount name.
---@param mount_name string
---@return boolean
function LOCKFILE.is_locked(mount_name)
  local f = io.open(lock_path(mount_name))
  if not f then return false end
  f:close()
  return true
end

return LOCKFILE
