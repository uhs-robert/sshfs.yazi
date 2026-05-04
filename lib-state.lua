-- lib-state.lua
local STATE = {}

local HOME = os.getenv("HOME")

STATE.KEY = {
  CONFIG = "CONFIG",
  HAS_FZF = "HAS_FZF",
}

---@param key string
---@param value any
STATE.set = ya.sync(function(state, key, value)
  state[key] = value
end)

---@param key string
---@return any
STATE.get = ya.sync(function(state, key)
  return state[key]
end)

--- Append a single line to a text file, creating it if it does not exist.
---@param path string
---@param line string
STATE.append_line = ya.sync(function(_, path, line)
  local f = io.open(path, "a")
  if f then
    f:write(line, "\n")
    f:close()
  end
end)

--- Read every non-empty line from a text file.
---@param path string
---@return string[]
STATE.read_lines = ya.sync(function(_, path)
  local lines, f = {}, io.open(path)
  if not f then return lines end
  for l in f:lines() do
    if #l > 0 then lines[#lines + 1] = l end
  end
  f:close()
  return lines
end)

--- Redirect all Yazi tabs whose cwd is inside `unmounted_url` back to home.
---@param unmounted_url string
STATE.redirect_tabs_to_home = ya.sync(function(_, unmounted_url)
  if not unmounted_url or unmounted_url == "" then return end
  for _, tab in ipairs(cx.tabs) do
    if tab.current.cwd:starts_with(unmounted_url) then
      ya.emit("cd", {
        HOME,
        tab = (type(tab.id) == "number" or type(tab.id) == "string") and tab.id or tab.id.value,
        raw = true,
      })
    end
  end
end)

return STATE
