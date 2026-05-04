-- ui-prompt.lua
local PROMPT = {}

--- Show a text input box and return the entered value, or nil if cancelled.
---@param title string
---@param is_password? boolean obscure input
---@param default? string pre-filled value
---@return string|nil
function PROMPT.input(title, is_password, default)
  local value, event = ya.input({
    title = title,
    value = default or "",
    obscure = is_password or false,
    pos = { "center", y = 3, w = 60 },
  })
  return event == 1 and value or nil
end

--- Shorthand for a password prompt.
---@param title string
---@return string|nil
function PROMPT.password(title)
  return PROMPT.input(title, true)
end

--- Ask the user which SSH user to connect as.
--- Returns the (possibly modified) alias, or nil if the user cancels.
---@param alias string SSH alias, e.g. "myserver" or "user@myserver"
---@param config table plugin config
---@return string|nil
function PROMPT.choose_user(alias, config)
  if config.default_user ~= "prompt" then return alias end

  local choice = ya.which({
    title = "Login as which user?",
    cands = {
      { on = "1", desc = "SSH config user (default)" },
      { on = "2", desc = "root" },
      { on = "3", desc = "Custom username" },
    },
  })
  if not choice then return nil end

  local hostname = alias:match("@(.+)$") or alias

  if choice == 1 then
    return alias
  elseif choice == 2 then
    return "root@" .. hostname
  elseif choice == 3 then
    local user = PROMPT.input("Enter username:")
    if not user or user == "" then return nil end
    return user .. "@" .. hostname
  end

  return alias
end

return PROMPT
