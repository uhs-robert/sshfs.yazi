-- ~/.config/yazi/plugins/sshfs/main.lua
-- SSHFS integration for Yazi

---@diagnostic disable: lowercase-global, undefined-global

-- Aliases
---@alias Stdio "PIPED" | "NULL" | "INHERIT"
---@alias Origin
---| "top-left"
---| "top-center"
---| "top-right"
---| "bottom-left"
---| "bottom-center"
---| "bottom-right"
---| "center"
---| "hovered"

-- Url object
---@class Url
---@field name string?
---@field stem string?
---@field frag string?
---@field parent Url?
---@field is_regular boolean
---@field is_search boolean
---@field is_archive boolean
---@field is_absolute boolean
---@field has_root boolean
---@field join fun(self: Url, another: Url | string): Url
---@field starts_with fun(self: Url, another: Url | string): boolean
---@field ends_with fun(self: Url, another: Url | string): boolean
---@field strip_prefix fun(self: Url, another: Url | string): Url
---@field __eq fun(self: Url, another: Url): boolean
---@field __tostring fun(self: Url): string
---@field __concat fun(self: Url, another: string): Url
---@field path fun(self: Url): string

-- Pos object
---@class Pos
---@field [1] Origin
---@field x integer? @X-offset relative to the origin (default: 0)
---@field y integer? @Y-offset relative to the origin (default: 0)
---@field w integer? @Width of the position (default: 0)
---@field h integer? @Height of the position (default: 0)

-- Ya global
---@class Ya
---@field uid fun(): integer
---@field notify fun(opts: { title: string, content: string, timeout: number, level: "info"|"warn"|"error"|nil }): nil
---@field dbg fun(... : any): nil
---@field err fun(... : any): nil
---@field sync fun(fn: fun(...: any): any): fun(...: any): any
---@field which fun(opts: { cands: { on: string|string[], desc: string? }[], silent: boolean? }): number?
---@field emit fun(cmd: string, args: { [integer|string]: nil | boolean | number | string | Url }): nil
---@field input fun(opts: { title: string, value: string?, obscure: boolean?, position: Pos, realtime: boolean?, debounce: number? }) : string? | integer

---@type Ya
ya = ya or {}

-- Command object
---@class Command
---@field arg fun(self: Command, arg: string): Command
---@field stdin fun(self: Command, mode: Stdio): Command
---@field stdout fun(self: Command, mode: Stdio): Command
---@field stderr fun(self: Command, mode: Stdio): Command
---@field env fun(self: Command, key: string, value: string): Command
---@field spawn fun(self: Command): Child, Error?
---@type fun(cmd: string): Command

-- Child object
---@class Child
---@field write_all fun(self: Child, input: string): boolean, Error?
---@field flush fun(self: Child): boolean, Error?
---@field wait_with_output fun(self: Child): Output?, Error?

-- Output from command
---@class Output
---@field stdout string
---@field stderr string
---@field status { code: number, success: boolean }

-- Error object
---@class Error
---@field message string

--=========== Plugin Settings =================================================
local isDebugEnabled = true
local M = {}
local PLUGIN_NAME = "sshfs"
local USER_ID = ya.uid()

--=========== Paths ===========================================================
local HOME = os.getenv("HOME")
local PLUGIN_DIR = HOME .. "/.config/yazi/plugins/sshfs.yazi"
local ROOT = HOME .. "/.cache/sshfs" -- mountpoints live here
local SAVE = PLUGIN_DIR .. "/sshfs.list" -- list of remembered aliases
local XDG_RUNTIME_DIR = os.getenv("XDG_RUNTIME_DIR") or ("/run/user/" .. USER_ID)

--================= Notify / Logger ===========================================
local Notify = {}

---@param level "info"|"warn"|"error"|nil
---@param s string
---@param ... any
function Notify._send(level, s, ...)
	debug(s, ...)
	local content = Notify._parseContent(s, ...)
	local entry = {
		title = PLUGIN_NAME,
		content = content,
		timeout = 3,
		level = level,
	}
	ya.notify(entry)
end

function Notify._parseContent(s, ...)
	local ok, content = pcall(string.format, s, ...)
	if not ok then
		content = s
	end
	content = tostring(content):gsub("[\r\n]+", " "):gsub("%s+$", "")
	return content
end

function Notify.error(...)
	ya.err(...)
	Notify._send("error", ...)
end
function Notify.warn(...)
	Notify._send("warn", ...)
end
function Notify.info(...)
	Notify._send("info", ...)
end
function debug(...)
	if isDebugEnabled then
		local msg = Notify._parseContent(...)
		ya.dbg(msg)
	end
end

--========= Run terminal commands =======================================================
---@param cmd string
---@param args? string[]
---@param input? string  -- optional stdin input (e.g., password)
---@return Error|true|nil, Output|nil
local function run_command(cmd, args, input)
	debug("Executing command: " .. cmd .. (args and #args > 0 and (" " .. table.concat(args, " ")) or ""))
	local msgPrefix = "Command: " .. cmd .. " - "
	local cmd_obj = Command(cmd)

	-- Add arguments
	if type(args) == "table" and #args > 0 then
		for _, arg in ipairs(args) do
			cmd_obj:arg(arg)
		end
	end

	-- Set stdin mode if input is provided
	if input then
		cmd_obj:stdin(Command.PIPED)
	else
		cmd_obj:stdin(Command.INHERIT)
	end

	-- Set other streams
	cmd_obj:stdout(Command.PIPED):stderr(Command.PIPED):env("XDG_RUNTIME_DIR", XDG_RUNTIME_DIR)

	local child, cmd_err = cmd_obj:spawn()
	if not child then
		Notify.error(msgPrefix .. "Failed to start. Error: %s", tostring(cmd_err))
		return cmd_err, nil
	end

	-- Send stdin input if available
	if input then
		local ok, err = child:write_all(input)
		if not ok then
			Notify.error(msgPrefix .. "Failed to write, stdin: %s", tostring(err))
			return err, nil
		end

		local flushed, flush_err = child:flush()
		if not flushed then
			Notify.error(msgPrefix .. "Failed to flush, stdin: %s", tostring(flush_err))
			return flush_err, nil
		end
	end

	-- Read output
	local output, out_err = child:wait_with_output()
	if not output then
		Notify.error(msgPrefix .. "Failed to get output, error: %s", tostring(out_err))
		return out_err, nil
	end

	-- Log outputs
	if output.stdout ~= "" then
		debug(msgPrefix, output.stdout)
	end
	if output.stderr ~= "" then
		return true, nil
	end
	if output.status and output.status.code ~= 0 then
		Notify.warn(msgPrefix .. "Error code `%s`, success: `%s`", output.status.code, tostring(output.status.success))
	end

	return nil, output
end

--======= SYNC HELPERS =======--

---Check whether a path exists on disk.
---@param path string
---@return boolean
local path_exists = ya.sync(function(_, path)
	local f = io.open(path)
	if f then
		f:close()
		return true
	end
	return false
end)

---`mkdir -p` if the directory does not yet exist.
---@param dir string
local function ensure_dir(dir)
	if path_exists(dir) then
		return
	end
	local err, _ = run_command("mkdir", { "-p", dir })
	if err then
		Notify.error("Failed to create directory: " .. dir .. " (" .. tostring(err) .. ")")
	end
end

---Append a single line to a text file, creating the parent dir if needed.
---@param path string
---@param line string
local append_line = ya.sync(function(_, path, line)
	local f = io.open(path, "a")
	if f then
		f:write(line, "\n")
		f:close()
	end
end)

---Read every non‑empty line from a text file.
---@param path string
---@return string[]
local read_lines = ya.sync(function(_, path)
	local lines, f = {}, io.open(path)
	if not f then
		return lines
	end
	for l in f:lines() do
		if #l > 0 then
			lines[#lines + 1] = l
		end
	end
	f:close()
	return lines
end)

---Redirect all tabs in mounted dir to home
---@param unmounted_url string
local redirect_unmounted_tabs_to_home = ya.sync(function(_, unmounted_url)
	debug("Url to redirect is `%s`", unmounted_url)
	if not unmounted_url or unmounted_url == "" then
		debug("Early exit")
		return
	end

	for _, tab in ipairs(cx.tabs) do
		if tab.current.cwd:starts_with(unmounted_url) then
			debug("Redirecting tab")
			ya.emit("cd", {
				HOME,
				tab = (type(tab.id) == "number" or type(tab.id) == "string") and tab.id or tab.id.value,
				raw = true,
			})
		end
	end
	debug("Function over")
end)

--=========== Utils =================================================

---Combines two lists
local function list_extend(a, b)
	local result = {}
	for _, v in ipairs(a) do
		table.insert(result, v)
	end
	for _, v in ipairs(b) do
		table.insert(result, v)
	end
	return result
end

---Filters a list to get unique values
local function unique(list)
	local seen, out = {}, {}
	for _, v in ipairs(list) do
		if not seen[v] then
			seen[v] = true
			out[#out + 1] = v
		end
	end
	return out
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
	debug("Prompting user for `%s`, is password: `%s`", title, is_password)
	local input_value, input_event = ya.input({
		title = title,
		value = value or "",
		obscure = is_password or false,
		position = { "top-center", y = 0, w = 60 },
	})

	if input_event ~= 1 then
		return nil
	end

	debug("Prompt result: `%s`", input_value)

	return input_value
end

--============== Helper functions ====================================

local function read_ssh_config_hosts()
	local list = {}
	local f = io.open(HOME .. "/.ssh/config")
	if not f then
		return list
	end
	for line in f:lines() do
		-- Only top-level Host lines in ~/.ssh/config are recognized.
		local host = line:match("^%s*Host%s+([^%s]+)")
		if host and host ~= "*" then
			list[#list + 1] = host
		end
	end
	f:close()
	return list
end

---Check if a mount point is actively mounted
---@param url Url
---@return boolean
local function is_mount_active(url)
	local files, _ = fs.read_dir(url, { limit = 1 })
	return files and #files > 0
end

---Lists all active mount points
---@return { alias: string, path: string }[]
local function list_mounts()
	local mounts = {}

	local files, err = fs.read_dir(Url(ROOT), { resolve = false })
	if not files then
		debug("No files in ROOT dir: %s", tostring(err))
		return mounts
	end

	for i, file in ipairs(files) do
		if file.cha.is_dir then
			local url = file.url
			if is_mount_active(url) then
				local alias = file.name
				debug("Active mount #%d: %s", i, url)
				mounts[#mounts + 1] = { alias = alias, path = tostring(url) }
			end
		end
	end

	debug("List Mounts: Found `%s` total", #mounts)

	return mounts
end

--=============== Handle unmount ============================================

---Remove a mountpoint
---@param mp string
local function remove_mountpoint(mp)
	local attempts = {
		{ "fusermount", { "-u", mp } },
		{ "fusermount3", { "-u", mp } },
		{ "umount", { "-l", mp } },
	}

	for _, cmd in ipairs(attempts) do
		local command, args = cmd[1], cmd[2]
		local err, _ = run_command(command, args)
		if err then
			return false
		end
		return true
	end

	return false
end

--======== Handle mount ============================================

---Tries sshfs via key authentication
---@param alias string
---@param mountPoint string
---@param mount_to_root boolean
local function try_key_auth(alias, mountPoint, mount_to_root)
	mount_to_root = mount_to_root or false
	local options = {
		"BatchMode=yes",
		"reconnect",
		"compression=yes",
		"ServerAliveInterval=15",
		"ServerAliveCountMax=3",
	}
	local remote_path = alias .. ":" .. (mount_to_root and "/" or "")
	local args = {
		remote_path,
		mountPoint,
		"-o",
		table.concat(options, ","),
	}
	return run_command("sshfs", args)
end

---Tries sshfs via password input, with retries allowed
---@param alias string
---@param mountPoint string
---@param mount_to_root boolean
---@param max_attempts? integer
---@return boolean? result, string? reason
local function try_password_auth(alias, mountPoint, mount_to_root, max_attempts)
	mount_to_root = mount_to_root or false
	max_attempts = max_attempts or 3
	local options = {
		"password_stdin",
		"reconnect",
		"compression=yes",
		"ServerAliveInterval=15",
		"ServerAliveCountMax=3",
	}
	local remote_path = alias .. ":" .. (mount_to_root and "/" or "")

	for attempt = 1, max_attempts do
		local pw = prompt(("Password for %s (%d/%d):"):format(alias, attempt, max_attempts), true)
		if not pw or pw == "" then
			return nil, "User aborted"
		end

		local args = {
			remote_path,
			mountPoint,
			"-o",
			table.concat(options, ","),
		}

		local err, _ = run_command("sshfs", args, pw .. "\n")
		if err then
			Notify.error("sshfs: authentication failed")
		else
			return true
		end
	end

	return false, "Authentication failed"
end

---Handles exit conditions after mount is done
---@param alias string
---@param mountPoint string
---@param jump boolean
local function finalize_mount(alias, mountPoint, jump)
	Notify.info(("Mounted “%s”"):format(alias))
	if jump then
		ya.emit("cd", { mountPoint, raw = true })
	end
end

---Adds a mountpoint
---@param alias string
---@param jump boolean
local function add_mountpoint(alias, jump)
	debug("Adding mountpoint: `%s`", alias)
	ensure_dir(ROOT)
	local mountPoint = ("%s/%s"):format(ROOT, alias)
	ensure_dir(mountPoint)

	-- If already exists, jump to it
	if is_mount_active(Url(mountPoint)) then
		return finalize_mount(alias, mountPoint, jump)
	end

	-- Ask user to go to home or root folder
	local mount_to_root = ya.which({
		title = "Mount where?",
		cands = {
			{ on = "1", desc = "Home directory (~)" },
			{ on = "2", desc = "Root directory (/)" },
		},
	}) == 2

	-- Try key authentication then try password if it fails
	local err, _ = try_key_auth(alias, mountPoint, mount_to_root)
	if not err then
		return finalize_mount(alias, mountPoint, jump)
	end

	local ok, reason = try_password_auth(alias, mountPoint, mount_to_root)
	if ok then
		return finalize_mount(alias, mountPoint, jump)
	elseif ok == false then
		Notify.error("Failed: " .. (reason or "unknown"))
	else
		debug("Aborted: " .. (reason or "user cancelled"))
	end
end

--=========== api actions =================================================
local function cmd_add_alias()
	local alias = prompt("Enter SSH host:")
	if alias == nil then
		return false
	elseif not alias:match("^[%w._-]+$") then
		Notify.error("Host must be alphanumeric with '.', '_', or '-' only")
		return
	end
	append_line(SAVE, alias)
	debug("Saved host alias `%s`", alias)
end

local function cmd_remove_alias()
	local saved_aliases = unique(read_lines(SAVE))
	local alias = choose("Remove which?", saved_aliases)
	if not alias then
		return
	end

	-- Filter out the alias
	local updated = {}
	for _, line in ipairs(saved_aliases) do
		if line ~= alias then
			table.insert(updated, line)
		end
	end

	-- Overwrite the SAVE file with updated lines
	local file, err = io.open(SAVE, "w")
	if not file then
		Notify.error("Failed to open save file: %s", tostring(err))
		return
	end
	for _, line in ipairs(updated) do
		file:write(line, "\n")
	end
	file:close()

	Notify.info(("Alias “%s” removed from saved list"):format(alias))
end

local function cmd_mount(args)
	-- Get alias_list
	local jump = args.jump == true
	local alias_list = unique(list_extend(read_lines(SAVE), read_ssh_config_hosts()))

	-- Choose alias to mount then add it
	local chosen_alias = (#alias_list == 1) and alias_list[1] or choose("Mount which host?", alias_list)
	if chosen_alias then
		add_mountpoint(chosen_alias, jump)
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
	-- get mounted dirs
	local mounts = list_mounts()
	if #mounts == 0 then
		Notify.warn("No SSHFS mounts are active")
		return
	end

	-- choose alias to unmount
	local aliases = {}
	for _, m in ipairs(mounts) do
		aliases[#aliases + 1] = m.alias
	end
	local alias = (#aliases == 1) and aliases[1] or choose("Unmount which?", aliases)
	if not alias then
		return
	end
	debug("Selected alias: `%s`", alias)

	-- find its mount‑point
	local mp
	for _, m in ipairs(mounts) do
		if m.alias == alias then
			debug("Matching Alias: `%s`, Path: `%s`", m.alias, m.path)
			mp = m.path
			break
		end
	end
	if not mp then
		Notify.error("Internal error: mount‑point not found")
		return
	end

	-- unmount it

	redirect_unmounted_tabs_to_home(mp)
	if remove_mountpoint(mp) then
		Notify.info("Unmounted “" .. alias .. "”")
	else
		Notify.error("Failed to unmount “" .. alias)
	end
end

--=========== public entry ================================================
local function check_dependencies()
	local err, _ = run_command("command", { "-v", "sshfs" })
	if err then
		Notify.error("sshfs is not installed or not in PATH")
		return false
	end
	return true
end

function M:setup()
	if not check_dependencies() then
		return
	end
	ensure_dir(ROOT)
	ensure_dir(PLUGIN_DIR)
end

---@param job {args: string[], args: {jump: boolean?, eject: boolean?, force: boolean?}}
function M:entry(job)
	local action = job.args[1]
	debug("SSHFS plugin invoked: action = `%s`", action)

	if action == "add" then
		cmd_add_alias()
	elseif action == "remove" then
		cmd_remove_alias()
	elseif action == "mount" then
		cmd_mount(job.args)
	elseif action == "jump" then
		cmd_jump()
	elseif action == "unmount" then
		cmd_unmount()
	else
		Notify.error("Unknown action")
	end

	debug("Finished running action: `%s`", action)
end

return M
