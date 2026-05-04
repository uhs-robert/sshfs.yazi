-- ui-picker.lua

local PICKER = {}

-- Forward declaration — choose() is mutually recursive with choose_filtered().
local choose

--- Present a which-key style menu (max 36 items).
---@param title string
---@param items string[]
---@return string|nil
function PICKER.menu(title, items)
  local keys = "1234567890abcdefghijklmnopqrstuvwxyz"
  local cands = {}
  for i, item in ipairs(items) do
    if i > #keys then break end
    cands[#cands + 1] = { on = keys:sub(i, i), desc = item }
  end
  local idx = ya.which({ title = title, cands = cands })
  return idx and items[idx]
end

--- Present an fzf picker with items piped via stdin.
---@param title string
---@param items string[]
---@return string|nil
function PICKER.fzf(title, items)
  local permit = ui.hide and ui.hide() or ya.hide()
  local result = nil

  local cmd = Command("fzf")
  for _, arg in ipairs({ "--prompt", title .. "> ", "--height", "100%", "--layout", "reverse", "--border" }) do
    cmd:arg(arg)
  end

  local child, err = cmd:stdin(Command.PIPED):stdout(Command.PIPED):stderr(Command.PIPED):spawn()
  if not child then
    local Notify = require(".lib-notify")
    Notify.error("Failed to start fzf: %s", tostring(err))
    permit:drop()
    return nil
  end

  child:write_all(table.concat(items, "\n"))
  child:flush()

  local output, wait_err = child:wait_with_output()
  if not output then
    local Notify = require(".lib-notify")
    Notify.error("Cannot read fzf output: %s", tostring(wait_err))
  elseif output.status.success and output.status.code ~= 130 and output.stdout ~= "" then
    result = output.stdout:match("^(.-)\n?$")
  elseif output.status.code ~= 130 then
    local Notify = require(".lib-notify")
    Notify.error("fzf exited with code %s: %s", output.status.code, output.stderr)
  end

  permit:drop()
  return result
end

--- Present a text-filter prompt then re-invoke choose() on the matching subset.
---@param title string
---@param items string[]
---@param config table
---@return string|nil
function PICKER.filtered(title, items, config)
  local Prompt = require(".ui-prompt")
  local query = Prompt.input(title .. " (filter)")
  if query == nil then return nil end

  local filtered = {}
  if query == "" then
    filtered = items
  else
    query = query:lower()
    for _, item in ipairs(items) do
      if item:lower():find(query, 1, true) then filtered[#filtered + 1] = item end
    end
  end

  if #filtered == 0 then
    local Notify = require(".lib-notify")
    Notify.warn("No items match your filter.")
    return nil
  end

  return choose(title, filtered, config)
end

--- Select the appropriate picker mode given the item count and config.
---@param count integer
---@param config table
---@return "fzf"|"menu"|"filter"
local function resolve_mode(count, config)
  local preferred = config.ui and config.ui.picker or "auto"
  local max = config.ui and config.ui.menu_max or 15
  local State = require(".lib-state")
  local has_fzf = State.get(State.KEY.HAS_FZF)

  if preferred == "fzf" then return has_fzf and "fzf" or "filter" end
  if count > max then return has_fzf and "fzf" or "filter" end
  return "menu"
end

--- Auto-select a picker and present items to the user.
--- Returns the chosen item, or nil if the user cancels.
---@param title string
---@param items string[]
---@param config? table defaults to current plugin config
---@return string|nil
choose = function(title, items, config)
  local State = require(".lib-state")
  config = config or State.get(State.KEY.CONFIG)
  if #items == 0 then return nil end
  if #items == 1 then return items[1] end

  local mode = resolve_mode(#items, config)
  local Notify = require(".lib-notify")
  Notify.debug("PICKER mode: %s (items=%d)", mode, #items)

  if mode == "fzf" then return PICKER.fzf(title, items) end
  if mode == "menu" then return PICKER.menu(title, items) end
  return PICKER.filtered(title, items, config)
end

PICKER.choose = choose

return PICKER
