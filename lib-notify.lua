-- lib-notify.lua
local NOTIFY = {}

local PLUGIN_NAME = "sshfs.yazi"
local Config = require(".config")
local TIMEOUTS = { error = 8, warn = 8, info = 3 }

---@param s string
---@param ... any
---@return string
local function parseContent(s, ...)
  local ok, content = pcall(string.format, s, ...)
  if not ok then content = s end
  return (tostring(content):gsub("[\r\n]+", " "):gsub("%s+$", ""))
end

---@param level "info"|"warn"|"error"|nil
---@param s string
---@param ... any
function NOTIFY._send(level, s, ...)
  NOTIFY.debug(s, ...)
  ya.notify({
    title = PLUGIN_NAME,
    content = parseContent(s, ...),
    timeout = TIMEOUTS[level] or 3,
    level = level,
  })
end

---@param ... any
function NOTIFY.error(...)
  ya.err(...)
  NOTIFY._send("error", ...)
end

---@param ... any
function NOTIFY.warn(...)
  NOTIFY._send("warn", ...)
end

---@param ... any
function NOTIFY.info(...)
  NOTIFY._send("info", ...)
end

---@param ... any
function NOTIFY.debug(...)
  local cfg = Config.get()
  if cfg and cfg.enable_debug then
    local msg = parseContent(...)
    ya.dbg(msg)
    if cfg.debug_log_file then
      local f = io.open(cfg.debug_log_file, "a")
      if f then
        f:write(os.date() .. " " .. msg .. "\n")
        f:close()
      end
    end
  end
end

return NOTIFY
