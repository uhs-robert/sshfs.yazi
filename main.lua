-- ~/.config/yazi/plugins/sshfs/main.lua
-- MVP: Basic SSHFS integration for Yazi
--
-- Commands for keymap.toml:
--   plugin sshfs -- add             → prompt & remember an SSH alias
--   plugin sshfs -- mount --jump    → choose alias, sshfs‑mount, jump into it
--   plugin sshfs -- unmount         → choose alias, fusermount ‑u
--   plugin sshfs -- jump            → jump to an existing mount

-- local ya = select(1, ...)
local M = {}
local PLUGIN_NAME = "sshfs"

--=========== paths ========================================================
local HOME = os.getenv("HOME")
local PLUGIN_DIR = HOME .. "/.config/yazi/plugins/sshfs.yazi"
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

---Show an input box.
---@param title string
---@param is_password boolean?
---@param value string?
---@return string|nil
local function prompt(title, is_password, value)
	local input_value, input_event = ya.input({
		title = title,
		value = value or "",
		obscure = is_password or false,
		pos = { "top-center", y = 0, w = 60 },
		-- TODO: remove this after next yazi released
		position = { "top-center", y = 0, w = 60 },
	})

	if input_event ~= 1 then
		return nil
	end

	return input_value
end

local function error(s, ...)
	ya.notify({ title = PLUGIN_NAME, content = string.format(s, ...), timeout = 3, level = "error" })
end

local function info(s, ...)
	ya.notify({ title = PLUGIN_NAME, content = string.format(s, ...), timeout = 3, level = "info" })
end

local function read_ssh_config_hosts()
	local list = {}
	local f = io.open(HOME .. "/.ssh/config")
	if not f then
		return list
	end
	for line in f:lines() do
		local host = line:match("^%s*Host%s+([^%s]+)")
		if host and host ~= "*" then
			list[#list + 1] = host
		end
	end
	f:close()
	return list
end

--=========== core actions =================================================
local function cmd_add()
	ya.dbg("trying to show prompt")
	local alias = prompt("SSH Host alias:")
	if alias == nil then
		return false
	elseif alias == "" then
		error("Alias cannot be empty")
	end
	append_line(SAVE, alias)
	info("Saved alias “" .. alias .. "”")
end

local function mount_alias(alias, jump)
	ensure_dir(ROOT)
	local mountPoint = string.format("%s/%s", ROOT, alias)
	ensure_dir(mountPoint)

	------------------------------------------------------------------
	-- 1. try key / agent authentication (NON‑interactive) ----------
	------------------------------------------------------------------
	local base = string.format(
		"sshfs %s: %q " .. "-o reconnect,compression=yes,ServerAliveInterval=15,ServerAliveCountMax=3" .. "",
		alias,
		mountPoint
	)
	local key_probe = base .. " -o BatchMode=yes"

	local _, how, code = os.execute(key_probe)
	if how == "exit" and code == 0 then -- key auth succeeded
		info(("Mounted “%s”"):format(alias))
		if jump then
			ya.emit("cd", { mountPoint, raw = true })
		end
		return
	end
	-- code==1  → auth failed, continue to password path
	-- any other error → abort
	if how ~= "exit" or code > 1 then
		error(("sshfs failed (%s,%s)"):format(how, code))
		return
	end

	------------------------------------------------------------------
	-- 2. fall‑back to password auth (three tries)  ------------------
	------------------------------------------------------------------
	local MAX = 3
	for attempt = 1, MAX do
		local pw = prompt(string.format("Password for %s  (%d/%d):", alias, attempt, MAX), true)
		if not pw then
			info("Mount aborted")
			return
		end

		-- pass ***exactly*** password + newline
		local cmd = string.format(" (printf '%%s\\n' %q) | %s -o password_stdin", pw, base)

		local _, how2, code2 = os.execute(cmd)
		if how2 == "exit" and code2 == 0 then -- success
			info(string.format("Mounted “%s”", alias))
			if jump then
				ya.emit("cd", { mountPoint, raw = true })
			end
			return
		else
			error("sshfs: authentication failed")
		end
	end

	error(string.format("Unable to mount “%s” after %d attempts", alias, MAX))
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
	-- Merge alias list from yazi with ssh_config
	for _, h in ipairs(read_ssh_config_hosts()) do
		table.insert(alias_list, h)
	end
	-- Choose host
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
			info("Unmounted " .. choice)
		end
	end
end

--=========== public entry ================================================
function M:setup()
	ensure_dir(ROOT)
	ensure_dir(PLUGIN_DIR)
end

---@param job {args: string[], args: {jump: boolean?, eject: boolean?, force: boolean?}}
function M:entry(job)
	local action = job.args[1]

	if action == "add" then
		print("add")
		cmd_add()
	elseif action == "mount" then
		cmd_mount(job.args)
	elseif action == "jump" then
		cmd_jump()
	elseif action == "unmount" then
		cmd_unmount()
	else
		error("Unknown action")
	end

	(ui.render or ya.render)()
end

return M
