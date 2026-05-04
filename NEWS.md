# ✨ What's New / 🚨 Breaking Changes

Please skim using the icons below for quick navigation, focus on what matters most to you:

- **(🚨) BREAKING CHANGE:** Breaking changes, respect the siren
- **(✨) Feat:** New features, follow the sparkles
- **(🔧) Internal:** Internal architectural changes, maintains a wrench

## ✨ v2.1: Custom remote paths, improved auth/ssh/sockets, modular architecture, new config options, and more

This is a massive update and complete overhaul of the plugin. It has been a long time coming, this brings `sshfs.yazi` up to date with my nvim plugin of the same nature: [sshfs.nvim](https://github.com/uhs-robert/sshfs.nvim).

### ✨ Feat: Custom path when mounting

When mounting a host you can now choose **Custom path...** from the picker and type any remote path on the fly.

Smart normalization handles edge cases:

- Blank input → `/`
- `~` or `~/foo` → passed through as-is
- `var/log` (no leading `/`) → normalized to `/var/log`

Pre-configured `host_paths` and `global_paths` still appear as quick-pick options.

---

### ✨ Feat: Proper SSH config resolution with `ssh -G`

The plugin now uses `ssh -G` to resolve host configurations. This ensures full compatibility with your `~/.ssh/config`, including:

- **`Include` directives**
- **`Match` blocks**
- **`ProxyJump` / `ProxyCommand`**
- **Hostname aliases and overrides**

---

### ✨ Feat: Interactive authentication (2FA, Password, Host Keys)

The plugin no longer prompts for passwords itself. Instead, it drops you into a temporary interactive terminal to handle authentication via the standard `ssh` client. This supports:

- **Password authentication**
- **2FA / Multi-factor prompts**
- **Host key verification** ("Are you sure you want to continue connecting?")
- **SSH agent challenges**

Once authenticated, a **ControlMaster** socket is established, allowing `sshfs` to mount instantly without further prompts so you can do subsequent actions like dropping into an SSH Terminal.

---

### ✨ Feat: Open SSH terminal to mount

You can now open a native interactive SSH terminal to any active mount using the **Terminal** command (`t` in menu, or `M t` by default).

This automatically leverages your existing ControlMaster socket for instant, passwordless access if the mount is active.

---

### ✨ Feat: New configuration options

```lua
require("sshfs"):setup({
  -- Remote paths offered for all hosts (in addition to ~ and /)
  global_paths = { "/var/log", "var/www", "/etc" },

  -- Per-host remote paths
  host_paths = {
    myserver = "/srv/www",
    devbox   = { "/home/deploy", "/opt/app" },
  },

  -- SSH ControlMaster connection reuse
  connections = {
    control_persist = "10m",
    socket_dir = os.getenv("HOME") .. "/.ssh/sockets",
  },

  -- Jump to mount dir automatically after a successful mount
  on_mount = { auto_jump = true },

  -- Delete empty mount directories after unmounting
  on_exit = { clean_mount_folders = true },
})
```

---

### ✨ Feat: Lifecycle hooks and connection pooling

- **`on_mount.auto_jump`**: Automatically jump into the mount directory after a successful mount.
- **`on_exit.clean_mount_folders`**: Automatically delete empty mount directories in `~/mnt/` after unmounting, keeping your system clean.
- **Connection pooling**: Leverages SSH `ControlMaster` to keep connections alive, making repeated mounts and command execution nearly instantaneous.

---

### 🔧 Internal: modular architecture

The plugin was refactored from a single `main.lua` (1,100+ lines) into focused library modules (`lib-ssh.lua`, `lib-sshfs.lua`, `lib-mount.lua`, `lib-hosts.lua`, etc.).

No user-facing changes here. All existing config keys and commands are fully compatible.

---

## 🚨 v2.0: Custom host file relocated (migration required)

### 🚨 BREAKING CHANGE: `sshfs.list` relocated to follow XDG Base Directory spec

The custom hosts file has moved from `~/.config/yazi/sshfs.list` to `$XDG_DATA_HOME/yazi/sshfs.list` (this is usually located in `~/.local/share/yazi/sshfs.list`).

If you have custom hosts saved, migrate your file before upgrading:

```bash
mv ~/.config/yazi/sshfs.list ~/.local/share/yazi/sshfs.list
```

If `$XDG_DATA_HOME` is set to a custom path, use that instead:

```bash
mv ~/.config/yazi/sshfs.list "$XDG_DATA_HOME/yazi/sshfs.list"
```

Hosts from `~/.ssh/config` are unaffected. Only manually added custom hosts need migration.
If you have no custom hosts then no action is needed.
