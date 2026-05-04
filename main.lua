-- main.lua
local M = {}

local CONFIG = require(".config")
local STATE = require(".lib-state")
local FS = require(".lib-fileservice")

--- Verify required system dependencies and detect optional ones.
---@return boolean
local function check_dependencies()
  local _, sshfs_err = Command("sshfs"):arg({ "--version" }):status()
  if sshfs_err then
    local Notify = require(".lib-notify")
    Notify.error("sshfs not found — is it installed and in PATH? PATH=%s", os.getenv("PATH") or "(unset)")
    return false
  end
  local _, fzf_err = Command("fzf"):arg({ "--version" }):status()
  STATE.set(STATE.KEY.HAS_FZF, not fzf_err)
  return true
end

--- Run first-use initialisation: dependency check and mount directory creation.
---@return boolean
local function init()
  if STATE.get("is_initialized") then return true end
  if not check_dependencies() then return false end
  local config = CONFIG.get()
  if not FS.ensure_dir(Url(config.mount_dir)) then
    local Notify = require(".lib-notify")
    Notify.error("Could not create mount directory: %s", config.mount_dir)
    return false
  end
  STATE.set("is_initialized", true)
  return true
end

--- Merge user config into defaults and persist to plugin state.
---@param cfg table|nil
function M:setup(cfg)
  if cfg == nil and type(self) == "table" and self ~= M then cfg = self end
  CONFIG.setup(cfg)
  local config = CONFIG.get()
  local parent = config.custom_hosts_file:match("^(.+)/[^/]+$")
  if parent then FS.ensure_dir(Url(parent)) end
end

--- Plugin entry point — dispatches `job.args[1]` to the matching command.
---@param job table
function M:entry(job)
  if not CONFIG.get() then CONFIG.setup() end
  if not init() then return end

  local Notify = require(".lib-notify")
  local Api = require(".api")
  local action = job.args[1]

  local handler = Api[action]
  if handler then
    Notify.debug("Entry action: %s", tostring(job.args[1]))
    handler(job.args)
  else
    Notify.error("Unknown entry action: %s", tostring(job.args[1]))
  end
end

return M
