-- main.lua
-- ~/.config/yazi/plugins/sshfs/main.lua
-- SSHFS integration for Yazi

--=========== Plugin Settings =================================================
local isDebugEnabled = false
local M = {}
local PLUGIN_NAME = "sshfs"
local USER_ID = ya.uid()
local XDG_RUNTIME_DIR = os.getenv("XDG_RUNTIME_DIR") or ("/run/user/" .. USER_ID)

--=========== Paths ===========================================================
local HOME = os.getenv("HOME")
local SSH_CONFIG = HOME .. "/.ssh/config"
local YAZI_DIR = HOME .. "/.config/yazi"
local SAVE_LIST = YAZI_DIR .. "/sshfs.list" -- list of remembered aliases

--=========== Plugin State ===========================================================
---@enum
local STATE_KEY = {
	CONFIG = "CONFIG",
	HAS_FZF = "HAS_FZF",
}

--=========== Host Cache ======================================================
local host_cache = {
	hosts = nil,
	ssh_config_mtime = 0,
	save_file_mtime = 0,
}

--================= Notify / Logger ===========================================
local TIMEOUTS = {
	error = 8,
	warn = 8,
	info = 3,
}
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
		timeout = TIMEOUTS[level] or 3,
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
---@param is_silent? boolean
---@return string|nil, Output|nil
local function run_command(cmd, args, input, is_silent)
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
		if not is_silent then
			Notify.error(msgPrefix .. "Failed to start. Error: %s", tostring(cmd_err))
		end
		return cmd_err and tostring(cmd_err), nil
	end

	-- Send stdin input if available
	if input then
		local ok, err = child:write_all(input)
		if not ok then
			if not is_silent then
				Notify.error(msgPrefix .. "Failed to write, stdin: %s", tostring(err))
			end
			return err and tostring(err), nil
		end

		local flushed, flush_err = child:flush()
		if not flushed then
			if not is_silent then
				Notify.error(msgPrefix .. "Failed to flush, stdin: %s", tostring(flush_err))
			end
			return flush_err and tostring(flush_err), nil
		end
	end

	-- Read output
	local output, out_err = child:wait_with_output()
	if not output then
		if not is_silent then
			Notify.error(msgPrefix .. "Failed to get output, error: %s", tostring(out_err))
		end
		return out_err and tostring(out_err), nil
	end

	-- Log outputs
	if output.stdout ~= "" and not is_silent then
		debug(msgPrefix .. "stdout: %s", output.stdout)
	end
	if output.status and output.status.code ~= 0 and not is_silent then
		Notify.warn(msgPrefix .. "Error code `%s`, success: `%s`", output.status.code, tostring(output.status.success))
	end

	-- Handle child output error
	if output.stderr ~= "" then
		if not is_silent then
			debug(msgPrefix .. "stderr: %s", output.stderr)
		end
		-- Only treat stderr as error if command actually failed
		if output.status and not output.status.success then
			return output.stderr, output
		end
	end

	return nil, output
end

--========= Sync helpers =======================================================
local set_state = ya.sync(function(state, key, value)
	state[key] = value
end)

local get_state = ya.sync(function(state, key)
	return state[key]
end)

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
		return
	end

	for _, tab in ipairs(cx.tabs) do
		if tab.current.cwd:starts_with(unmounted_url) then
			debug("Redirecting unmounted tab home")
			ya.emit("cd", {
				HOME,
				tab = (type(tab.id) == "number" or type(tab.id) == "string") and tab.id or tab.id.value,
				raw = true,
			})
		end
	end
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

--- Deep merge two tables: overrides take precedence
---@param defaults table
---@param overrides table|nil
---@return table
local function deep_merge(defaults, overrides)
	if type(overrides) ~= "table" then
		return defaults
	end

	local result = {}

	for k, v in pairs(defaults) do
		if type(v) == "table" and type(overrides[k]) == "table" then
			result[k] = deep_merge(v, overrides[k])
		else
			result[k] = overrides[k] ~= nil and overrides[k] or v
		end
	end

	-- Include any keys in overrides not in defaults
	for k, v in pairs(overrides) do
		if result[k] == nil then
			result[k] = v
		end
	end

	return result
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
		position = { "center", y = 3, w = 60 },
	})

	if input_event ~= 1 then
		return nil
	end

	return input_value
end

---Present a simple which‑key style selector and return the chosen item (Max: 36 options).
---@param title string
---@param items string[]
---@return string|nil
local function choose_which(title, items)
	local keys = "1234567890abcdefghijklmnopqrstuvwxyz"
	local candidates = {}
	for i, item in ipairs(items) do
		if i > #keys then
			break
		end
		candidates[#candidates + 1] = { on = keys:sub(i, i), desc = item }
	end

	local idx = ya.which({ title = title, cands = candidates })
	return idx and items[idx]
end

---@param title string
---@param items string[]
---@return string|nil
local function choose_with_fzf(title, items)
	local permit = ya.hide()
	local result = nil

	local items_str = table.concat(items, "\n")
	local args = {
		"--prompt",
		title .. "> ",
		"--height",
		"100%",
		"--layout",
		"reverse",
		"--border",
	}

	local cmd = Command("fzf")
	for _, arg in ipairs(args) do
		cmd:arg(arg)
	end

	local child, err = cmd:stdin(Command.PIPED):stdout(Command.PIPED):stderr(Command.PIPED):spawn()
	if not child then
		Notify.error("Failed to start `fzf`: %s", tostring(err))
		permit:drop()
		return nil
	end

	child:write_all(items_str)
	child:flush()

	local output, wait_err = child:wait_with_output()
	if not output then
		Notify.error("Cannot read `fzf` output: %s", tostring(wait_err))
	else
		if output.status.success and output.status.code ~= 130 and output.stdout ~= "" then
			result = output.stdout:match("^(.-)\n?$")
		elseif output.status.code ~= 130 then
			Notify.error("`fzf` exited with error code %s. Stderr: %s", output.status.code, output.stderr)
		end
	end

	permit:drop()
	return result
end

local choose

---Shows a filterable list for the user to choose from.
---@param title string
---@param items string[]
---@param config table|nil Optional config to avoid state retrieval
---@return string|nil
local function choose_filtered(title, items, config)
	local query = prompt(title .. " (filter)")
	if query == nil then
		return nil
	end

	local filtered_items = {}
	if query == "" then
		filtered_items = items
	else
		query = query:lower()
		for _, item in ipairs(items) do
			if item:lower():find(query, 1, true) then
				table.insert(filtered_items, item)
			end
		end
	end

	if #filtered_items == 0 then
		Notify.warn("No items match your filter.")
		return nil
	end

	-- After filtering, restart the choose decision matrix
	return choose(title, filtered_items, config)
end

---@param count integer
---@param max integer
---@param preferred "auto"|"fzf"
---@return "fzf"|"menu"|"filter"
local function get_picker(count, max, preferred)
	local has_fzf = get_state(STATE_KEY.HAS_FZF)
	if preferred == "fzf" then
		return has_fzf and "fzf" or "filter"
	else
		if count > max then
			return has_fzf and "fzf" or "filter"
		else
			return "menu"
		end
	end
end

---Present a prompt to choose from a picker
---@param title string
---@param items string[]
---@param config table|nil Optional config to avoid state retrieval
---@return string|nil
choose = function(title, items, config)
	config = config or get_state(STATE_KEY.CONFIG)
	local picker = config.ui.picker or "auto"
	local max = config.ui.menu_max or 15

	debug("Picker: %s, max: %d", picker, max)

	if #items == 0 then
		return nil
	elseif #items == 1 then
		return items[1]
	end

	local mode = get_picker(#items, max, picker)

	debug("Mode: %s", mode)

	if mode == "fzf" then
		return choose_with_fzf(title, items)
	elseif mode == "menu" then
		return choose_which(title, items)
	elseif mode == "filter" then
		return choose_filtered(title, items, config)
	end
end

--============== File helpers ====================================
---Check if a path exists and is a directory
---@param url Url
---@return boolean
local function is_dir(url)
	local cha, _ = fs.cha(url)
	return cha and cha.is_dir or false
end

---Check if a directory is empty (more efficient than reading all entries)
---@param url Url
---@return boolean
local function is_dir_empty(url)
	local files, _ = fs.read_dir(url, { limit = 1 })
	return type(files) == "table" and #files == 0
end

--- Make directory path if the directory does not yet exist.
---@param url Url
---@return boolean
local function ensure_dir(url)
	local cha, _ = fs.cha(url)
	if cha and cha.is_dir then
		debug("`%s` is dir", url.name)
		return true
	end

	local _, err = fs.create("dir_all", url)
	if err then
		Notify.error("Failed to create directory: " .. tostring(url) .. " (" .. tostring(err) .. ")")
		return false
	end
	return true
end

---Get file modification time
---@param path string
---@return integer
local function get_file_mtime(path)
	local url = Url(path)
	local cha, _ = fs.cha(url)
	return cha and cha.mtime or 0
end

local function read_ssh_config_hosts()
	local list = {}
	local f = io.open(SSH_CONFIG)
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

--============== Cache state management ====================================
---Check if host cache is valid by comparing file modification times
---@return boolean
local function is_host_cache_valid()
	local ssh_config_mtime = get_file_mtime(SSH_CONFIG)
	local save_file_mtime = get_file_mtime(SAVE_LIST)

	return (
		host_cache.hosts ~= nil
		and host_cache.ssh_config_mtime == ssh_config_mtime
		and host_cache.save_file_mtime == save_file_mtime
	)
end

---Update host cache with current file modification times
---@param hosts string[]
local function update_host_cache(hosts)
	local ssh_config_mtime = get_file_mtime(SSH_CONFIG)
	local save_file_mtime = get_file_mtime(SAVE_LIST)

	host_cache.hosts = hosts
	host_cache.ssh_config_mtime = ssh_config_mtime
	host_cache.save_file_mtime = save_file_mtime
end

---Get list of all available hosts (from SSH config and custom list)
---@return string[]
local function get_all_hosts()
	if is_host_cache_valid() then
		return host_cache.hosts
	end

	local ssh_config_hosts = read_ssh_config_hosts()
	local hosts

	-- Check if custom hosts file exists
	local url = Url(SAVE_LIST)
	local cha, _ = fs.cha(url)

	if cha then
		-- Custom hosts file exists - combine SSH config and saved hosts
		local saved_hosts = read_lines(SAVE_LIST)
		hosts = unique(list_extend(saved_hosts, ssh_config_hosts))
	else
		-- No custom hosts file - only use SSH config
		hosts = ssh_config_hosts
	end

	update_host_cache(hosts)
	return hosts
end

--============== Mount helpers ====================================
--- Parses `mount` output to find sshfs paths under a given root
---@param mount_output string
---@param root string
---@return string[] -- list of absolute mount paths
local function parse_sshfs_mounts(mount_output, root)
	local mounts = {}
	local root_escaped = root:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
	local pattern = "^.+%son%s(" .. root_escaped .. "/.-)%s+type%s+fuse%.sshfs"

	for line in mount_output:gmatch("[^\r\n]+") do
		local path = line:match(pattern)
		if path then
			mounts[#mounts + 1] = path
		end
	end

	return mounts
end

---Check if a mount point is actively mounted
---@param path string
---@param url Url
---@param mount_dir string
---@return boolean
local function is_mount_active(path, url, mount_dir)
	if not is_dir(url) then
		return false
	end

	local err, output = run_command("mount", nil, nil, true) --silent
	if err or not output then
		debug("Failed to get mount info in is_mount_active(), falling back to directory scan")
		return not is_dir_empty(url)
	end

	local mounts = parse_sshfs_mounts(output.stdout, mount_dir)
	for _, mounted_path in ipairs(mounts) do
		if mounted_path == path then
			return true
		end
	end

	return false
end

---Lists all active mount points
---@param mount_dir string
---@return { alias: string, path: string }[]
local function list_mounts(mount_dir)
	local mounts = {}

	local mountErr, output = run_command("mount", nil, nil, true) --silent
	if mountErr or not output then
		debug("Failed to get mount info in list_mounts(), falling back to directory scan")
		local files, err = fs.read_dir(Url(mount_dir), { resolve = false })
		if not files then
			debug("No files in mount_dir dir: %s", tostring(err))
			return mounts
		end

		for i, file in ipairs(files) do
			local url = file.url
			local path = tostring(url)
			if is_dir(url) and is_mount_active(path, url, mount_dir) then
				local alias = file.name
				debug("Active mount #%d: %s", i, url)
				mounts[#mounts + 1] = { alias = alias, path = path }
			end
		end
	else
		for _, path in ipairs(parse_sshfs_mounts(output.stdout, mount_dir)) do
			local alias = path:match("([^/]+)$")
			if alias then
				debug("Active mount: %s", path)
				mounts[#mounts + 1] = { alias = alias, path = path }
			end
		end
	end

	debug("List Mounts: Found `%s` total", #mounts)
	return mounts
end

--======== Unmount functions ============================================
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
		local err, _ = run_command(command, args, nil, true) -- silent
		if not err then
			fs.remove("dir_clean", Url(mp)) -- clean the empty dir
			return true
		end
	end

	return false
end

--======== Mount functions ============================================
---Get sshfs user config options
---@param type "key"|"password"
---@param config table|nil Optional config to avoid state retrieval
local function getConfigForSSHFS(type, config)
	config = config or get_state(STATE_KEY.CONFIG)
	if not config then
		return {}
	end

	local options = {}

	-- Handle key vs password auth (essential for sshfs functionality)
	if type == "key" then
		table.insert(options, "BatchMode=yes")
	else
		table.insert(options, "password_stdin")
	end

	-- Use sshfs options
	if config.sshfs_options and #config.sshfs_options > 0 then
		for _, sshfs_opt in ipairs(config.sshfs_options) do
			table.insert(options, sshfs_opt)
		end
	end

	return options
end

---Tries sshfs via key authentication
---@param alias string
---@param mountPoint string
---@param mount_to_root boolean
---@param config table|nil Optional config to avoid state retrieval
---@return string|nil err_msg, Output|nil output
local function try_key_auth(alias, mountPoint, mount_to_root, config)
	mount_to_root = mount_to_root or false
	local options = getConfigForSSHFS("key", config)

	local remote_path = alias .. ":" .. (mount_to_root and "/" or "")
	local args = {
		remote_path,
		mountPoint,
		"-o",
		table.concat(options, ","),
	}

	local err, output = run_command("sshfs", args, nil, true) --silent
	if output and output.status and output.status.success then
		return nil, output
	end

	return err, output
end

---Tries sshfs via password input, with retries allowed
---@param alias string
---@param mountPoint string
---@param mount_to_root boolean
---@param config table|nil Optional config to avoid state retrieval
---@return boolean? result, string? reason
local function try_password_auth(alias, mountPoint, mount_to_root, config)
	mount_to_root = mount_to_root or false
	config = config or get_state(STATE_KEY.CONFIG)
	local max_attempts = (config and config.password_attempts) or 3
	local options = getConfigForSSHFS("password", config)
	local remote_path = alias .. ":" .. (mount_to_root and "/" or "")
	local args = {
		remote_path,
		mountPoint,
		"-o",
		table.concat(options, ","),
	}

	debug("Attempting password authentication for %s with options: %s", alias, table.concat(options, ","))

	local last_err
	for attempt = 1, max_attempts do
		local pw = prompt(("Password for %s (%d/%d):"):format(alias, attempt, max_attempts), true)
		if not pw or pw == "" then
			return nil, "User aborted"
		end
		local err, _ = run_command("sshfs", args, pw .. "\n", true) --silent
		if not err then
			return true, nil
		end
		last_err = err
		-- Continue to next attempt if we haven't reached max_attempts
	end

	-- All attempts failed
	return false, last_err
end

---Handles exit conditions after mount is done
---@param alias string
---@param mountPoint string
---@param jump boolean
local function finalize_mount(alias, mountPoint, jump)
	Notify.info(("Mounted %s"):format(alias))
	if jump then
		ya.emit("cd", { mountPoint, raw = true })
	end
end

---Adds a mountpoint
---@param alias string
---@param jump boolean
local function add_mountpoint(alias, jump)
	local config = get_state(STATE_KEY.CONFIG)
	local mount_dir = config.mount_dir
	ensure_dir(Url(mount_dir))
	local mountPoint = ("%s/%s"):format(mount_dir, alias)
	local mountUrl = Url(mountPoint)
	ensure_dir(mountUrl)

	-- If already exists, jump to it
	if is_mount_active(mountPoint, mountUrl, mount_dir) then
		return finalize_mount(alias, mountPoint, jump)
	end

	-- Use config default or ask user to go to home or root folder
	local map = { root = true, home = false }
	local mount_to_root = map[config.default_mount_point]
	if mount_to_root == nil then
		mount_to_root = ya.which({
			title = "Mount where?",
			cands = {
				{ on = "1", desc = "Home directory (~)" },
				{ on = "2", desc = "Root directory (/)" },
			},
		}) == 2
	end

	-- Try key authentication, then try password authentication as fallback
	local err_key_auth = try_key_auth(alias, mountPoint, mount_to_root, config)
	if not err_key_auth then
		return finalize_mount(alias, mountPoint, jump)
	end

	-- Key auth failed → always try password authentication as fallback
	local ok, pass_err = try_password_auth(alias, mountPoint, mount_to_root, config)
	if ok then
		return finalize_mount(alias, mountPoint, jump)
	elseif ok == false then
		Notify.error("Authentication failed: " .. (pass_err or "unknown"))
	else
		-- User cancelled password prompt
	end

	-- error or abort clean up
	fs.remove("dir_clean", mountUrl) -- clean empty dir
end

local function check_alias_exists(alias)
	for _, saved_alias in ipairs(read_lines(SAVE_LIST)) do
		if saved_alias == alias then
			return true
		end
	end
	return false
end

--=========== api actions =================================================
local function cmd_add_alias()
	local alias = prompt("Enter SSH host:")
	if alias == nil then
		return false
	elseif not alias:match("^[%w_.%-@]+:?[%w%-%.]*$") then
		Notify.error("Host must be a valid SSH host string")
		return
	elseif check_alias_exists(alias) then
		Notify.warn("Host already exists")
		return
	end
	append_line(SAVE_LIST, alias)
	debug("Saved host alias `%s`", alias)

	-- Update cache
	if host_cache.hosts then
		-- Add the new alias to the existing cache
		local found = false
		for _, existing_alias in ipairs(host_cache.hosts) do
			if existing_alias == alias then
				found = true
				break
			end
		end
		if not found then
			table.insert(host_cache.hosts, alias)
		end
		-- Update the save file mtime
		host_cache.save_file_mtime = get_file_mtime(SAVE_LIST)
	end
end

local function cmd_remove_alias()
	-- Check if custom hosts file exists
	local url = Url(SAVE_LIST)
	local cha, _ = fs.cha(url)

	if not cha then
		Notify.warn("No custom hosts to remove")
		return
	end

	-- Choose from saved aliases
	local config = get_state(STATE_KEY.CONFIG)
	local saved_aliases = read_lines(SAVE_LIST)
	local alias = choose("Remove which?", saved_aliases, config)
	if not alias then
		return
	end

	-- Filter out the chosen alias
	local updated = {}
	for _, line in ipairs(saved_aliases) do
		if line ~= alias then
			table.insert(updated, line)
		end
	end

	-- If no hosts remain, delete the file
	if #updated == 0 then
		fs.remove("file", url)
		debug("Deleted empty custom hosts file")
	else
		-- Overwrite the save list file with updated lines
		local file, err = io.open(SAVE_LIST, "w")
		if not file then
			Notify.error("Failed to open save file: %s", tostring(err))
			return
		end
		for _, line in ipairs(updated) do
			file:write(line, "\n")
		end
		file:close()
	end

	-- Update cache
	if host_cache.hosts then
		-- Remove the alias from the existing cache
		local new_hosts = {}
		for _, existing_alias in ipairs(host_cache.hosts) do
			if existing_alias ~= alias then
				table.insert(new_hosts, existing_alias)
			end
		end
		host_cache.hosts = new_hosts
		-- Update the save file mtime
		host_cache.save_file_mtime = get_file_mtime(SAVE_LIST)
	end

	Notify.info(("Alias “%s” removed from saved list"):format(alias))
end

local function cmd_mount(args)
	local config = get_state(STATE_KEY.CONFIG)
	-- Get alias_list
	local jump = args.jump == true
	local alias_list = get_all_hosts()
	-- Choose alias to mount then add it
	local chosen_alias = (#alias_list == 1) and alias_list[1] or choose("Mount which host?", alias_list, config)
	if chosen_alias then
		add_mountpoint(chosen_alias, jump)
	end
end

local function cmd_jump()
	-- Get active mounts
	local config = get_state(STATE_KEY.CONFIG)
	local mount_dir = config.mount_dir
	local mounts = list_mounts(mount_dir)
	if #mounts == 0 then
		return Notify.warn("No active mounts to jump to")
	end
	-- Choose mount to jump to
	local labels = {}
	for _, m in ipairs(mounts) do
		labels[#labels + 1] = m.alias
	end
	local choice = (#labels == 1) and labels[1] or choose("Jump to mount", labels, config)
	-- Jump to directory
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
	-- Get active mounts
	local config = get_state(STATE_KEY.CONFIG)
	local mount_dir = config.mount_dir
	local mounts = list_mounts(mount_dir)
	if #mounts == 0 then
		Notify.warn("No SSHFS mounts are active")
		return
	end
	-- choose alias to unmount
	local aliases = {}
	for _, m in ipairs(mounts) do
		aliases[#aliases + 1] = m.alias
	end
	local alias = (#aliases == 1) and aliases[1] or choose("Unmount which?", aliases, config)
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

local function cmd_open_mount_dir()
	local config = get_state(STATE_KEY.CONFIG)
	local mount_dir = config.mount_dir
	ya.emit("cd", { mount_dir, raw = true })
end

local function cmd_open_ssh_config()
	ya.emit("cd", { HOME .. "/.ssh/", raw = true })
end

local function cmd_menu()
	local choice = ya.which({
		title = "SSHFS Menu",
		cands = {
			{ on = "m", desc = "Mount & jump" },
			{ on = "u", desc = "Unmount" },
			{ on = "a", desc = "Add host" },
			{ on = "r", desc = "Remove host" },
			{ on = "h", desc = "Go to mount home" },
			{ on = "c", desc = "Open ~/.ssh/config" },
		},
	})

	if choice == 1 then
		cmd_mount({ jump = true })
	elseif choice == 2 then
		cmd_unmount()
	elseif choice == 3 then
		cmd_add_alias()
	elseif choice == 4 then
		cmd_remove_alias()
	elseif choice == 5 then
		cmd_open_mount_dir()
	elseif choice == 6 then
		cmd_open_ssh_config()
	end
end

--=========== init requirements ================================================

---Verify all dependencies
local function check_dependencies()
	-- Check for sshfs
	local sshfs_err, _ = run_command("sshfs", { "--version" }, nil, true)
	if sshfs_err then
		local path = os.getenv("PATH") or "(unset)"
		Notify.error("sshfs not found. Is it installed and in PATH? PATH=" .. path)
		return false
	end

	-- Check for fzf (optional dependency)
	local fzf_err, _ = run_command("fzf", { "--version" }, nil, true)
	set_state(STATE_KEY.HAS_FZF, not fzf_err)
	return true
end

---Verify mount dir exists
local function check_has_mount_directory()
	local config = get_state(STATE_KEY.CONFIG)
	local mount_dir = config.mount_dir
	return ensure_dir(Url(mount_dir))
end

---Initialize the plugin, verify all dependencies
local function init()
	local initialized = get_state("is_initialized")
	if not initialized then
		if not check_dependencies() then
			Notify.error("Missing sshfs dependency, please install sshfs and try again...")
			return false
		end
		if not check_has_mount_directory() then
			Notify.error("Could not create mount directory")
			return false
		end
		initialized = true
		set_state("is_initialized", true)
	end
	return initialized
end

--=========== Plugin start =================================================
-- Default configuration
local default_config = {
	mount_dir = HOME .. "/mnt",
	password_attempts = 3, -- Number of password attempts before giving up
	default_mount_point = "auto",
	-- Default sshfs options
	sshfs_options = {
		"reconnect",
		"ConnectTimeout=5",
		"compression=yes",
		"ServerAliveInterval=15",
		"ServerAliveCountMax=3",
	},
	ui = {
		menu_max = 15, -- can go up to 36
		picker = "auto",
	},
}

---Merges user‑provided configuration options into the defaults.
---@param user_config table|nil
local function set_plugin_config(user_config)
	local config = deep_merge(default_config, user_config or {})
	set_state(STATE_KEY.CONFIG, config)
end

---Setup
function M:setup(cfg)
	set_plugin_config(cfg)
end

---Entry
function M:entry(job)
	if not init() then
		return
	end

	local action = job.args[1]
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
	elseif action == "home" then
		cmd_open_mount_dir()
	elseif action == "menu" then
		cmd_menu()
	else
		Notify.error("Unknown action")
	end
end

return M
