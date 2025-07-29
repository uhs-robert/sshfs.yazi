-- ~/.config/yazi/plugins/sshfs/main.lua
-- MVP: Basic SSHFS integration for Yazi
--
-- Commands for keymap.toml:
--   plugin sshfs -- add             → prompt & remember an SSH alias
--   plugin sshfs -- mount --jump    → choose alias, sshfs‑mount, jump into it
--   plugin sshfs -- unmount         → choose alias, fusermount ‑u
--   plugin sshfs -- jump            → jump to an existing mount

local ya = select(1, ...)
local M = {}

--=========== paths ========================================================
local HOME = os.getenv("HOME")
local PLUGIN_DIR = HOME .. "/.config/yazi/plugins/sshfs" -- keep everything self‑contained
local ROOT = HOME .. "/.cache/sshfs" -- mountpoints live here
local SAVE = PLUGIN_DIR .. "/sshfs.list" -- list of remembered aliases

--=========== tiny helpers =================================================
---Execute a shell command (formatted like string.format).
---@param fmt string
---@param ... any
local function sh(fmt, ...)
	os.execute(string.format(fmt, ...))
end

---Check whether a path exists on disk.
---@param path string
---@return boolean
local function path_exists(path)
	local file = io.open(path)
	if file then
		file:close()
		return true
	end
	return false
end

---`mkdir -p` if the directory does not yet exist.
---@param dir string
local function ensure_dir(dir)
	if not path_exists(dir) then
		sh("mkdir -p %q", dir)
	end
end

---Read every non‑empty line from a text file.
---@param path string
---@return string[]
local function read_lines(path)
	local lines, file = {}, io.open(path)
	if not file then
		return lines
	end
	for line in file:lines() do
		if #line > 0 then
			lines[#lines + 1] = line
		end
	end
	file:close()
	return lines
end

---Append a single line to a text file, creating the parent dir if needed.
---@param path string
---@param line string
local function append_line(path, line)
	ensure_dir(path:gsub("/[^/]+$", "")) -- parent directory
	local file = assert(io.open(path, "a"))
	file:write(line, "\n")
	file:close()
end

---Present a simple which‑key style selector and return the chosen item.
---@param title string
---@param items string[]
---@return string|nil
local function choose(title, items)
	if #items == 0 then
		return nil
	end
	local candidates = {}
	for index, item in ipairs(items) do
		candidates[#candidates + 1] = { on = tostring(index), desc = item }
	end
	local idx = ya.which({ title = title, cands = candidates })
	return idx and items[idx]
end

--=========== core actions =================================================
local function cmd_add()
	local alias = ya.input("SSH Host alias:")
	if alias and alias ~= "" then
		append_line(SAVE, alias)
		ya.notify({ title = "sshfs", content = "Saved alias " .. alias, timeout = 2 })
	end
end

local function mount_alias(alias, jump)
	ensure_dir(ROOT)
	local mount_path = string.format("%s/%s", ROOT, alias)
	ensure_dir(mount_path)
	sh(
		"sshfs %s: %q -o reconnect,compression=yes,ServerAliveInterval=15,ServerAliveCountMax=3,allow_other -o nonempty &",
		alias,
		mount_path
	)
	ya.notify({ title = "sshfs", content = "Mounting " .. alias, timeout = 1 })
	if jump then
		ya.emit("cd", { mount_path, raw = true })
	end
end

local function list_mounts()
	local mounts = {}
	for _, alias in ipairs(read_lines(SAVE)) do
		local mount_path = string.format("%s/%s", ROOT, alias)
		if path_exists(mount_path) then
			mounts[#mounts + 1] = { alias = alias, path = mount_path }
		end
	end
	return mounts
end

local function cmd_mount(args)
	local jump = args.jump == true
	local alias_list = read_lines(SAVE)
	local chosen_alias = (#alias_list == 1) and alias_list[1] or choose("Mount which host?", alias_list)
	if chosen_alias then
		mount_alias(chosen_alias, jump)
	end
end

local function cmd_jump()
	local mounts = list_mounts()
	if #mounts == 0 then
		return
	end
	local labels = {}
	for _, m in ipairs(mounts) do
		labels[#labels + 1] = m.alias
	end
	local choice = (#labels == 1) and labels[1] or choose("Jump to mount", labels)
	if not choice then
		return
	end
	for _, m in ipairs(mounts) do
		if m.alias == choice then
			ya.emit("cd", { m.path, raw = true })
		end
	end
end

local function cmd_unmount()
	local mounts = list_mounts()
	if #mounts == 0 then
		return
	end
	local labels = {}
	for _, m in ipairs(mounts) do
		labels[#labels + 1] = m.alias
	end
	local choice = (#labels == 1) and labels[1] or choose("Unmount which?", labels)
	if not choice then
		return
	end
	for _, m in ipairs(mounts) do
		if m.alias == choice then
			sh("fusermount -u %q", m.path)
			ya.notify({ title = "sshfs", content = "Unmounted " .. choice, timeout = 2 })
		end
	end
end

--=========== public entry ================================================
function M.setup()
	ensure_dir(ROOT)
	ensure_dir(PLUGIN_DIR)
end

function M.entry(job)
	local action = job.args[1]
	if action == "--" then
		action = job.args[2]
	end -- safety for keymap parser

	if action == "add" then
		cmd_add()
	elseif action == "mount" then
		cmd_mount(job.args)
	elseif action == "jump" then
		cmd_jump()
	elseif action == "unmount" then
		cmd_unmount()
	else
		ya.notify({ title = "sshfs", content = "Unknown action", level = "error" })
	end

	(ya.render or ui.render)()
end

return M
