<p align="center">
  <img
    src="https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/svg/1f4e1.svg"
    width="128" height="128" alt="SSH emoji" />
</p>
<h1 align="center">sshfs.yazi</h1>

<p align="center">
  <a href="https://github.com/uhs-robert/sshfs.yazi/stargazers"><img src="https://img.shields.io/github/stars/uhs-robert/sshfs.yazi?colorA=192330&colorB=khaki&style=for-the-badge&cacheSeconds=4300" alt="Stargazers"></a>
  <a href="https://github.com/sxyazi/yazi" target="_blank" rel="noopener noreferrer"><img alt="Yazi 0.25+" src="https://img.shields.io/badge/Yazi-0.25%2B-blue?style=for-the-badge&cacheSeconds=4300&labelColor=192330" alt="Yazi"></a>
  <a href="https://github.com/uhs-robert/sshfs.yazi/issues"><img src="https://img.shields.io/github/issues/uhs-robert/sshfs.yazi?colorA=192330&colorB=skyblue&style=for-the-badge&cacheSeconds=4300" alt="Issues"></a>
  <a href="https://github.com/uhs-robert/sshfs.yazi/contributors"><img src="https://img.shields.io/github/contributors/uhs-robert/sshfs.yazi?colorA=192330&colorB=8FD1C7&style=for-the-badge&cacheSeconds=4300" alt="Contributors"></a>
  <a href="https://github.com/uhs-robert/sshfs.yazi/network/members"><img src="https://img.shields.io/github/forks/uhs-robert/sshfs.yazi?colorA=192330&colorB=CFA7FF&style=for-the-badge&cacheSeconds=4300" alt="Forks"></a>
</p>

<p align="center">
A minimal, blazing fast <strong>SSHFS</strong> integration for the <a target="_blank" rel="noopener noreferrer" href="https://github.com/sxyazi/yazi">Yazi</a> terminal file‑manager.
</p>
<p align="center">
  <a href="./NEWS.md">✨ What's New / 🚨 Breaking Changes</a>
</p>

## 🕶️ What does it do?

sshfs.yazi mounts hosts from your SSH config and makes them accessible locally.

You can **browse**, **search**, or **open SSH terminals** across multiple mounts from within Yazi. Uses sockets to persist your authentication/connections.

Built using the best of both `SSHFS` and `SSH` in tandem with your existing tools.

<https://github.com/user-attachments/assets/fa4029d5-874e-47a1-b281-80b8ce42f860>

> [!NOTE]
>
> **Linux/Mac Only**
>
> This plugin currently only supports Linux/Mac. You can [help add Windows support](https://github.com/uhs-robert/sshfs.yazi/issues/4) if interested.

## ✨ Features

- **Robust SSH config resolution** – Full support for `Include`, `Match`, `ProxyJump`, and hostname aliases via `ssh -G`.
- **Interactive Authentication** – Handles passwords, 2FA, and host key verification by dropping you into a terminal shell when needed.
- **Connection Pooling** – Leverages SSH `ControlMaster` sockets for persistent connections.
- **Smart Path Selection** – Choose between home, root, or custom paths on the fly.
- **Configurable Paths** – Define `global_paths` or per-host `host_paths` for quick access to frequently used remote directories.
- **Integrated Picker** – Seamlessly switch between a which-key style menu, `fzf` (if installed), or a filterable list.
- **Lifecycle Hooks** – Automatically jump to mounts on success and clean up empty mount directories on exit.
- **SSH Terminal Shell** - After mount, use SSH `ControlMaster` socket to automatically drop into an SSH shell and back to yazi when done.

## 🧠 What it does under the hood

This plugin serves as a wrapper for the `sshfs` command, integrating it seamlessly with Yazi. It resolves host configurations using `ssh -G` to ensure full compatibility with complex SSH configs (including `Include`, `Match`, and `ProxyJump` directives).

Authentication is handled interactively via a temporary terminal shell, which naturally supports passwords, 2FA, and host key verification. Once authenticated, the plugin establishes an SSH `ControlMaster` socket to persist the connection, allowing `sshfs` to mount instantly and subsequent operations to run without repeated prompts.

The plugin automatically reads hosts from your `~/.ssh/config` file and maintains a separate list of custom hosts stored in `$XDG_DATA_HOME/yazi/sshfs.list` (or `~/.local/share/yazi/sshfs.list`).

The core default `sshfs` command used is as follows (you may tweak these options and the mount directory with your setup settings):

```sh
# Mount home directory
sshfs user@host: ~/mnt/alias -o reconnect,compression=yes,ServerAliveInterval=15,ServerAliveCountMax=3

# Mount specific remote directory (when configured in alias)
sshfs user@host:/var/log ~/mnt/alias-var-log -o reconnect,compression=yes,ServerAliveInterval=15,ServerAliveCountMax=3
```

## 📋 Requirements

| Software   | Minimum       | Notes                               |
| ---------- | ------------- | ----------------------------------- |
| Yazi       | `>=25.5.31`   | untested on 25.6+                   |
| sshfs      | any           | `sudo dnf/apt/pacman install sshfs` |
| fusermount | from FUSE     | Usually pre-installed on Linux      |
| SSH config | working hosts | Hosts come from `~/.ssh/config`     |

> [!NOTE]
> For Mac users, see the macOS setup steps below.

---

### 🍏 macOS Setup

To use **sshfs.yazi** on macOS, follow these steps:

1. **Install macFUSE**
   Download and install macFUSE from the official site:
   [https://macfuse.github.io/](https://macfuse.github.io/)

2. **Install SSHFS for macFUSE**
   Use the official SSHFS releases compatible with macFUSE:
   [https://github.com/macfuse/macfuse/wiki/File-Systems-%E2%80%90-SSHFS](https://github.com/macfuse/macfuse/wiki/File-Systems-%E2%80%90-SSHFS)

3. **Install Yazi**
   On macOS via Homebrew:

   ```sh
   brew install yazi
   ```

## 📦 Installation

Install the plugin via Yazi's package manager:

```sh
ya pkg add uhs-robert/sshfs
```

Then add the following to your `~/.config/yazi/init.lua` to enable the plugin with default settings:

```lua
require("sshfs"):setup()
```

## 🎹 Key Mapping

### 🗝️ Recommended: Preset keymaps

Add this to your `~/.config/yazi/keymap.toml` for a conflict-free approach that automatically picks up the latest updates and works well with your other plugins:

```toml
[mgr]
prepend_keymap = [
  { on = ["M","s"], run = "plugin sshfs -- menu",            desc = "Open SSHFS options" },
]
```

The `M s` menu provides access to all SSHFS functions:

- `m` → Mount & jump
- `u` → Unmount
- `t` → Terminal
- `a` → Add host
- `r` → Remove host
- `h` → Go to mount home
- `c` → Open ~/.ssh/config
- `l` → Open custom host list

> [!TIP]
> The examples in this README all use the [array form for keymaps](https://yazi-rs.github.io/docs/configuration/keymap).
> You must pick **only one style** per file; mixing with `[[mgr.prepend_keymap]]` will fail.
>
> **Also note:** some plugins (e.g., `mount.yazi`) suggest binding a bare key like `on = "M"`,
> which blocks all `M <key>` chords (including `M s`). You can change those to chords
> (e.g. `["M","m"]`) or choose a different prefix.

---

### 🛠️ Alternative: Custom direct keymaps

If you prefer fully custom and direct keymaps, you may also set your own using our API. Be sure to **watch** for new releases so you don't miss the latest features.

Here are the available options from the default preset above:

```toml
[mgr]
prepend_keymap = [
  { on = ["M","m"], run = "plugin sshfs -- mount --jump",    desc = "Mount & jump" },
  { on = ["M","u"], run = "plugin sshfs -- unmount",         desc = "Unmount SSHFS" },
  { on = ["M","t"], run = "plugin sshfs -- terminal",        desc = "SSH Terminal" },
  { on = ["M","a"], run = "plugin sshfs -- add",             desc = "Add SSH host" },
  { on = ["M","r"], run = "plugin sshfs -- remove",          desc = "Remove SSH host" },
  { on = ["M","h"], run = "plugin sshfs -- home",            desc = "Go to mount home" },
  { on = ["M","c"], run = "cd ~/.ssh/",                      desc = "Go to ssh config" },
  { on = ["M","l"], run = "plugin sshfs -- hosts",           desc = "Open custom host list" },
]
```

> [!IMPORTANT]
> If you choose to use direct keymaps, you will be responsible for managing and resolving any conflicts yourself.

## 🚀 Usage

### 📝 Example using the default recommended preset

- **SSHFS Menu (`M s`):** Opens an interactive menu with all SSHFS options
  - **Mount (`M m`):** Choose a host and select a remote directory (`~` home, `/` root, or **Custom path...** to type any arbitrary path like `/var/log` or `etc/nginx`). This works for hosts from your `~/.ssh/config` and any custom hosts you've added. Custom hosts with specific remote paths configured will mount directly to that path.
  - **Unmount (`M u`):** Choose an active mount to unmount it.
  - **Terminal (`M t`):** Open an interactive SSH terminal to a mounted host.
  - **Add host (`M a`):** Enter a custom host (`user@host`) and optionally specify a remote directory (e.g., `/var/log`, `/etc/nginx`) to create an alias for that specific path. When you mount this alias later, it will go directly to that remote directory. This is useful for frequently accessed remote directories or quick testing. For persistent, system-wide access, updating your `.ssh/config` is recommended.
  - **Remove host (`M r`):** Select and remove any Yazi-only hosts that you've added.
  - **Jump to mount home directory (`M h`):** Jump to the mount home directory.
  - **Open custom host list (`M l`):** Navigate to the directory containing your custom hosts file for direct editing.

## 💡 Tips and Performance

- If automatic key authentication fails, the plugin will prompt for a password/2FA/etc interactively by dropping you into a terminal shell.
- SSH keys vastly speed up repeated mounts (no password prompt), leverage your `ssh_config` rather than manually adding hosts to make this as easy as possible.
- **User Selection**: By setting `default_user = "prompt"` in your configuration, you can choose which user to login as when mounting (SSH config user, root, or custom username). This is useful when you need to switch between different user contexts on the same host. The default setting (`"auto"`) respects your SSH config without prompting.

## ⚙️ Configuration

> [!WARNING]
> This section is intended for power users (which should be _all of you_ since you're using SSH).
> Skip this if you only want to run the default settings.

To customize plugin behavior, you may pass a config table to `setup()` (default settings are displayed for optional configuration):

```lua
require("sshfs"):setup({
  -- Custom hosts file
  custom_hosts_file = (os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")) .. "/yazi/sshfs.list",

  -- Mount directory
  mount_dir = os.getenv("HOME") .. "/mnt",

  -- Default mount point: Go to home, root, or always ask where to go
  default_mount_point = "auto", -- "auto" | "home" | "root"

  -- Default user selection: Use SSH config user or prompt for choice (useful with multiple users per host)
  default_user = "auto", -- "auto" | "prompt"

  -- Remote paths offered to all hosts when mounting (in addition to ~ and /)
  global_paths = {
     -- Optionally define default mount paths for ALL hosts
    -- These appear as options when connecting to any host
    -- Examples:
    -- "~/.config",
    -- "/var/www",
    -- "/srv",
    -- "/opt"
    -- "/var/log",
    -- "/etc",
    -- "/tmp",
    -- "/usr/local",
    -- "/data",
    -- "/var/lib",
  },

  -- Per-host remote paths offered when mounting that host
  host_paths = {
    -- Optionally define default mount paths for specific hosts
    -- These are shown in addition to global_paths
    --   myserver = "/srv/www",
    --   devbox   = { "/home/deploy", "/opt/app" },
  },

  -- SSHFS mount options (array of strings)
  -- These options are passed directly to the sshfs command
  sshfs_options = {
    "reconnect",                      -- Auto-reconnect on connection loss
    "ConnectTimeout=5",               -- Connection timeout in seconds
    "compression=yes",                -- Enable compression
    "ServerAliveInterval=15",         -- Keep-alive interval (15s × 3 = 45s timeout)
    "ServerAliveCountMax=3",          -- Keep-alive message count
    -- "dir_cache=yes",               -- Enable directory caching (default: yes)
    -- "dcache_timeout=300",          -- Cache timeout in seconds
    -- "dcache_max_size=10000",       -- Max cache size
    -- "allow_other",                 -- Allow other users to access mount
    -- "uid=1000,gid=1000",           -- Set file ownership
    -- "follow_symlinks",             -- Follow symbolic links
  },

  -- SSH ControlMaster connection reuse settings
  connections = {
    control_persist = "10m",                           -- How long to keep the master socket alive after last use
    socket_dir = os.getenv("HOME") .. "/.ssh/sockets", -- Where ControlMaster sockets are stored
  },

  -- Behavior after a successful mount
  on_mount = {
    auto_jump = true, -- Jump to the mount directory automatically
  },

  -- Cleanup behavior after unmounting
  on_exit = {
    clean_mount_folders = true, -- Delete empty mount directories after unmounting
  },

  -- Picker UI settings
  ui = {
    -- Maximum number of items to show in the menu picker.
    -- If the list exceeds this number, a different picker (like fzf) is used.
    menu_max = 15, -- Recommended: 10–20. Max: 36.

    -- Picker strategy:
    -- "auto":  uses menu if items <= menu_max, otherwise fzf (if available) or a filterable list
    picker = "auto", -- "auto" | "fzf" | "menu"
  },
})
```

All sshfs options are specified in the `sshfs_options` array. You can learn more about [sshfs mount options here](https://man7.org/linux/man-pages/man1/sshfs.1.html).

In addition, sshfs also supports a variety of options from [sftp](https://man7.org/linux/man-pages/man1/sftp.1.html) and [ssh_config](https://man7.org/linux/man-pages/man5/ssh_config.5.html).

---

### 📝 Advanced Configuration Examples

Here are some common sshfs option combinations:

```lua
-- Minimal reliable setup
require("sshfs"):setup({
  sshfs_options = {
    "reconnect",
    "ServerAliveInterval=15",
    "ServerAliveCountMax=3",
  },
})

-- Performance optimized
require("sshfs"):setup({
  sshfs_options = {
    "reconnect",
    "compression=yes",
    "cache_timeout=300",
    "ConnectTimeout=10",
    "dir_cache=yes",
    "dcache_timeout=600",
  },
})

-- Multi-user access
require("sshfs"):setup({
  sshfs_options = {
    "reconnect",
    "allow_other",
    "uid=1000,gid=1000",
    "umask=022",
    "ServerAliveInterval=30",
  },
})
```
