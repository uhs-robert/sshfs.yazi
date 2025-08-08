# 🧲 sshfs.yazi

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Yazi](https://img.shields.io/badge/Yazi-25.5%2B-blue)](https://github.com/sxyazi/yazi)
[![GitHub stars](https://img.shields.io/github/stars/uhs-robert/sshfs.yazi?style=social)](https://github.com/uhs-robert/sshfs.yazi/stargazers)
[![GitHub issues](https://img.shields.io/github/issues-raw/uhs-robert/sshfs.yazi)](https://github.com/uhs-robert/sshfs.yazi/issues)


A minimal, fast **SSHFS** integration for the [Yazi](https://github.com/sxyazi/yazi) terminal file‑manager.

Mount any host from your `~/.ssh/config`, or add custom hosts, and browse remote files as if they were local. Jump between your local machine and remote mounts with a single keystroke.

<https://github.com/user-attachments/assets/b7ef109a-0941-4879-b15a-a343262f0967>

> [!NOTE]
>
> **Linux Only (for now!)**
>
> This plugin currently supports Linux only.
> If you're interested in helping add support for other platforms, check out the open issues:
>
> - [Add macOS support](https://github.com/uhs-robert/sshfs.yazi/issues/3)
> - [Add Windows support](https://github.com/uhs-robert/sshfs.yazi/issues/4)
>
> If you have some Lua experience (or want to learn), I’d be happy to walk you through integration and testing. Pull requests are welcome!

## 🤔 Why SSHFS?

- **Works anywhere you have SSH access.** No VPN, NFS or Samba needed – only port 22.
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

## 📦 Installation

Install the plugin via Yazi's package manager:

```sh
# via Yazi’s package manager
ya pack -a uhs-robert/sshfs
```

Then add the following to your `~/.config/yazi/init.lua` to enable the plugin with default settings:

```lua
require("sshfs"):setup()
```

## ⚙️ Configuration

To customize plugin behavior, you may pass a config table to `setup()` (default settings are displayed):

```lua
require("sshfs"):setup({
  -- Mount directory
  mount_dir = "~/mnt",

  -- Set connection timeout when connecting to server (in seconds).
  connect_timeout = 5,

  -- Enable or disable compression.
  compression = true,

  -- Interval to send keep-alive messages to the server.
  server_alive_interval = 15,

  -- Number of keep-alive messages to send before disconnecting.
  server_alive_count_max = 3,

  -- Enable or disable directory caching.
  dir_cache = false,

  -- Directory cache timeout in seconds.
  -- Only applies if dir_cache is enabled.
  dcache_timeout = 300,

  -- Maximum size of the directory cache.
  -- Only applies if dir_cache is enabled.
  dcache_max_size = 10000,

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

These configuration options apply to the `sshfs` command. You can learn more about [sshfs mount options here](https://man7.org/linux/man-pages/man1/sshfs.1.html).

In addition, sshfs also supports a variety of options from [sftp](https://man7.org/linux/man-pages/man1/sftp.1.html) and [ssh_config](https://man7.org/linux/man-pages/man5/ssh_config.5.html).

## 🎹 Key Mapping

Add the following to your `~/.config/yazi/keymap.toml`. You can customize keybindings to your preference.

```toml
[mgr]
prepend_keymap = [
  { on = ["M","m"], run = "plugin sshfs -- mount --jump",    desc = "Mount & jump" },
  { on = ["M","u"], run = "plugin sshfs -- unmount",         desc = "Unmount SSHFS" },
  { on = ["M","a"], run = "plugin sshfs -- add",             desc = "Add SSH host" },
  { on = ["M","r"], run = "plugin sshfs -- remove",          desc = "Remove SSH host" },
  { on = ["M","h"], run = "plugin sshfs -- home",            desc = "Go to mount home" },
  { on = ["M","c"], run = "cd ~/.ssh/",                      desc = "Go to ssh config" },
  { on = ["g","m"], run = "plugin sshfs -- jump",            desc = "Jump to mount" },
]
```

## 🚀 Usage

- **Mount (`M m`):** Choose a host and select a remote directory (`~` or `/`). This works for hosts from your`~/.ssh/config` and any custom hosts you've added.
- **Unmount (`M u`):** Choose an active mount to unmount it.
- **Add host (`M a`):** Enter a custom host (`user@host`) for Yazi-only use (useful for quick testing or temp setups). For persistent, system-wide access, updating your `.ssh/config` is recommended.
- **Remove host (`M r`):** Select and remove any Yazi-only hosts that you've added.
- **Jump to mount (`g m`):** Jump to any active mount from another tab or location.
- **Jump to mount home directory (`M h`):** Jump to the mount home directory.

## 💡 Tips and Performance

- If key authentication fails, the plugin will prompt for a password up to 3 times before giving up.
- SSH keys vastly speed up repeated mounts (no password prompt), leverage your `ssh_config` rather than manually adding hosts to make this as easy as possible.

## 📜 License

This plugin is released under the MIT license. Please see the [LICENSE](https://github.com/uhs-robert/sshfs.yazi?tab=MIT-1-ov-file) file for details.
