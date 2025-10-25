<p align="center">
  <img
    src="https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/svg/1f4e1.svg"
    width="128" height="128" alt="SSH emoji" />
</p>
<h1 align="center">sshfs.yazi</h1>

<p align="center">
  <a href="https://github.com/uhs-robert/sshfs.yazi/stargazers"><img src="https://img.shields.io/github/stars/uhs-robert/sshfs.yazi?colorA=192330&colorB=skyblue&style=for-the-badge"></a>
  <a href="https://github.com/sxyazi/yazi" target="_blank" rel="noopener noreferrer"><img alt="Yazi 0.25+" src="https://img.shields.io/badge/Yazi-0.25%2B-blue?style=for-the-badge&labelColor=192330" /></a>
  <a href="https://github.com/uhs-robert/sshfs.yazi/issues"><img src="https://img.shields.io/github/issues/uhs-robert/sshfs.yazi?colorA=192330&colorB=khaki&style=for-the-badge"></a>
  <a href="https://github.com/uhs-robert/sshfs.yazi/contributors"><img src="https://img.shields.io/github/contributors/uhs-robert/sshfs.yazi?colorA=192330&colorB=8FD1C7&style=for-the-badge"></a>
  <a href="https://github.com/uhs-robert/sshfs.yazi/network/members"><img src="https://img.shields.io/github/forks/uhs-robert/sshfs.yazi?colorA=192330&colorB=CFA7FF&style=for-the-badge"></a>
</p>

<p align="center">
A minimal, blazing fast <strong>SSHFS</strong> integration for the <a target="_blank" rel="noopener noreferrer" href="https://github.com/sxyazi/yazi">Yazi</a> terminal file‑manager.
</p>

## 🕶️ What does it do?

Mount any host from your `~/.ssh/config`, or add custom hosts, and browse remote files as if they were local. Jump between your local machine and remote mounts with a single keystroke.

<https://github.com/user-attachments/assets/b7ef109a-0941-4879-b15a-a343262f0967>

> [!NOTE]
>
> **Linux/Mac Only (for now!)**
>
> This plugin currently only supports Linux/Mac.
> If you're interested in helping add support for other platforms, check out the open issues:
>
> - [Add Windows support](https://github.com/uhs-robert/sshfs.yazi/issues/4)
>
> If you have some Lua experience (or want to learn), I’d be happy to walk you through integration and testing. Pull requests are welcome!

## 🤔 Why SSHFS?

- **Works anywhere you have SSH access.** Nothing extra is needed – only port 22.
- **Treat remote files like local ones.** Run `vim`, `nvim`, `sed`, preview images / videos directly, etc.
- **User‑space, unprivileged.** No root required; mounts live under your chosen mount directory or the default (`~/mnt`).
- **Bandwidth‑friendly.** SSH compression, connection timeout, and reconnect options are enabled by default.
- **Quick Loading and Operations.** Load / edit files quickly without any lag and use all the tools from your local machine.

Perfect for tweaking configs, deploying sites, inspecting logs, or just grabbing / editing / deleting files remotely.

## 🧠 What it does under the hood

This plugin serves as a wrapper for the `sshfs` command, integrating it seamlessly with Yazi. It automatically reads hosts from your `~/.ssh/config` file. Additionally, it maintains a separate list of custom hosts in `~/.config/yazi/sshfs.list`.

The core default `sshfs` command used is as follows (you may tweak these options and the mount directory with your setup settings):

```sh
sshfs user@host: ~/mnt/alias -o reconnect,compression=yes,ServerAliveInterval=15,ServerAliveCountMax=3
```

## ✨ Features

- **One‑key mounting** – remembers your SSH hosts and reads from your `ssh_config`.
- **Jump/Return workflow** – quickly copy files between local & remote.
- Uses `sshfs` directly.
- Mount‑points live under your chosen mount directory (default: `~/mnt`), keeping them isolated from your regular file hierarchy.

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

### 🗝️ Recommended: Preset

Add this to your `~/.config/yazi/keymap.toml` for a conflict-free approach that works well with other plugins:

```toml
[mgr]
prepend_keymap = [
  { on = ["M","s"], run = "plugin sshfs -- menu",            desc = "Open SSHFS options" },
]
```

The `M s` menu provides access to all SSHFS functions:

- `m` → Mount & jump
- `u` → Unmount
- `j` → Jump to mount
- `a` → Add host
- `r` → Remove host
- `h` → Go to mount home
- `c` → Open ~/.ssh/config

> [!TIP]
> `sshfs.yazi` uses the [array form for keymaps](https://yazi-rs.github.io/docs/configuration/keymap).
> You must pick **only one style** per file; mixing with `[[mgr.prepend_keymap]]` will fail.
>
> **Also note:** some plugins (e.g., `mount.yazi`) bind a bare key like `on = "M"`,
> which blocks all `M <key>` chords (including `M s`). Change those to chords
> (e.g. `["M","m"]`) or choose a different prefix.

---

### 🛠️ Alternative: Custom direct keybinds

If you prefer direct keybinds, you may also set your own using our API. Here are the available options from the default preset:

```toml
[mgr]
prepend_keymap = [
  { on = ["M","m"], run = "plugin sshfs -- mount --jump",    desc = "Mount & jump" },
  { on = ["M","u"], run = "plugin sshfs -- unmount",         desc = "Unmount SSHFS" },
  { on = ["M","j"], run = "plugin sshfs -- jump",            desc = "Jump to mount" },
  { on = ["M","a"], run = "plugin sshfs -- add",             desc = "Add SSH host" },
  { on = ["M","r"], run = "plugin sshfs -- remove",          desc = "Remove SSH host" },
  { on = ["M","h"], run = "plugin sshfs -- home",            desc = "Go to mount home" },
  { on = ["M","c"], run = "cd ~/.ssh/",                      desc = "Go to ssh config" },
]
```

> [!IMPORTANT]
> If you choose to use direct keybinds, you will be responsible for managing and handling any conflicts yourself.

## 🚀 Usage

### 📝 Example using the recommended preset

- **SSHFS Menu (`M s`):** Opens an interactive menu with all SSHFS options
  - **Mount (`M m`):** Choose a host and select a remote directory (`~` or `/`). This works for hosts from your `~/.ssh/config` and any custom hosts you've added.
  - **Unmount (`M u`):** Choose an active mount to unmount it.
  - **Jump to mount (`M j`):** Jump to any active mount from another tab or location
  - **Add host (`M a`):** Enter a custom host (`user@host`) for Yazi-only use (useful for quick testing or temp setups). For persistent, system-wide access, updating your `.ssh/config` is recommended.
  - **Remove host (`M r`):** Select and remove any Yazi-only hosts that you've added.
  - **Jump to mount home directory (`M h`):** Jump to the mount home directory.

## 💡 Tips and Performance

- If key authentication fails, the plugin will prompt for a password up to 3 times before giving up.
- SSH keys vastly speed up repeated mounts (no password prompt), leverage your `ssh_config` rather than manually adding hosts to make this as easy as possible.

## ⚙️ Configuration

> [!WARNING]
> This section is intended for power users only.
> Skip this if you only want to run the default settings.
> Keep reading for advanced SSHFS customization and plugin configuration options.

To customize plugin behavior, you may pass a config table to `setup()` (default settings are displayed for optional configuration):

```lua
require("sshfs"):setup({
  -- Mount directory
  mount_dir = os.getenv("HOME") .. "/mnt",

  -- Password authentication attempts before giving up
  password_attempts = 3,

  -- Default mount point: Go to home, root, or always ask where to go
  default_mount_point = "auto" -- home | root | auto

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

  -- Picker UI settings
  ui = {
    -- Maximum number of items to show in the menu picker.
    -- If the list exceeds this number, a different picker (like fzf) is used.
    menu_max = 15, -- Recommended: 10–20. Max: 36.

    -- Picker strategy:
    -- "auto": uses menu if items <= menu_max, otherwise fzf (if available) or a filterable list
    -- "fzf": always use fzf if available, otherwise fallback to a filterable list
    picker = "auto", -- "auto" | "fzf"
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
