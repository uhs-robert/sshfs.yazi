-- lib-fileservice.lua

local FS = {}

--- Check if a path exists and is a directory.
---@param url Url
---@return boolean
function FS.is_dir(url)
  local cha, _ = fs.cha(url)
  return cha and cha.is_dir or false
end

--- Check if a directory is empty.
---@param url Url
---@return boolean
function FS.is_dir_empty(url)
  local files, _ = fs.read_dir(url, { limit = 1 })
  return type(files) == "table" and #files == 0
end

--- Create a directory (and parents) if it does not already exist.
---@param url Url
---@return boolean
function FS.ensure_dir(url)
  local cha, _ = fs.cha(url)
  if cha and cha.is_dir then return true end
  local _, err = fs.create("dir_all", url)
  if err then
    local Notify = require(".lib-notify")
    Notify.error("Failed to create directory: %s (%s)", tostring(url), tostring(err))
    return false
  end
  return true
end

--- Return the modification time of a file, or 0 if it does not exist.
---@param path string
---@return integer
function FS.get_mtime(path)
  local cha, _ = fs.cha(Url(path))
  return cha and cha.mtime or 0
end

return FS
