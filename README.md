# sshfs.yazi

A minimal, fast **SSHFS** integration for the [Yazi](https://github.com/sxyazi/yazi) terminal file‑manager.

Mount any host from your `~/.ssh/config`, or add custom hosts, and browse remote files as if they were local. Jump between your local machine and remote mounts with a single keystroke.

> [!NOTE]
>
> **This plugin only supports Linux**
>
> If this tool is something that you're interested in seeing on Mac or Windows and you have some Lua experience then feel free to reach out. I'll be happy to walk you through integration and testing. I am open to any pull request that will add this support!

<!--toc:start-->

- [sshfs.yazi](@sshfs.yazi)
  - [Preview](#preview)
  - [Why SSHFS](#why-sshfs)
  - [What it does under the hood](#what-it-does-under-the-hood)
  - [Features](#features)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Key Mapping](#key-mapping)
  - [Usage](#usage)
  - [Tips and Performance](#tips-and-performance)
  <!--toc:end-->

## Preview

```text
M m  → Mount a host from your ~/.ssh/config and jump into it
M u  → Unmount an active connection
g m  → Jump to any active mount
M a  → Add a new custom SSH host
M r  → Remove a custom SSH host
```

https://github.com/user-attachments/assets/bab05a7b-60e1-403b-86b8-8dafa10273f5

## Why SSHFS?

- **Works anywhere you have SSH access.** No VPN, NFS or Samba needed – only port 22.
- **Treat remote files like local ones.** Run `vim`, `nvim`, `sed`, preview images / videos directly, etc.
- **User‑space, unprivileged.** No root required; mounts live under `~/.cache/sshfs`.
- **Bandwidth‑friendly.** SSH compression and reconnect options are enabled by default.
- **Quick Loading and Operations.** Load / edit files quickly without any lag and use all the tools from your local machine.

Perfect for tweaking configs, deploying sites, inspecting logs, or just grabbing / editing / deleting files remotely.

## What it does under the hood

This plugin serves as a wrapper for the `sshfs` command, integrating it seamlessly with Yazi. It automatically reads hosts from your `~/.ssh/config` file. Additionally, it maintains a separate list of custom hosts in `~/.config/yazi/plugins/sshfs.yazi/sshfs.list`. The core `sshfs` command used is:

```sh
sshfs user@host: ~/.cache/sshfs/alias -o reconnect,compression=yes,ServerAliveInterval=15,ServerAliveCountMax=3
```

## Features

- **One‑key mounting** – remembers your SSH hosts and reads from your `ssh_config`.
- **Jump/Return workflow** – quickly copy files between local & remote.
- Uses `sshfs` directly.
- Mount‑points live under `~/.cache/sshfs`, keeping them isolated from your regular file hierarchy.

## Requirements

| Software   | Minimum       | Notes                               |
| ---------- | ------------- | ----------------------------------- |
| Yazi       | `>=25.5.31`   | tested on 25.6+                     |
| sshfs      | any           | `sudo dnf/apt/pacman install sshfs` |
| fusermount | from FUSE     | Usually pre-installed on Linux      |
| SSH config | working hosts | Hosts come from `~/.ssh/config`     |

## Installation

```sh
# via Yazi’s package manager
ya pack -a uhs-robert/sshfs
```

Modify your `~/.config/yazi/init.lua` to include:

```lua
require("sshfs"):setup()
```

## Key Mapping

Add the following to your `~/.config/yazi/keymap.toml`. You can customize keybindings to your preference.

```toml
[mgr]
prepend_keymap = [
  { on = ["M","a"], run = "plugin sshfs -- add",             desc = "Add SSH host" },
  { on = ["M","r"], run = "plugin sshfs -- remove",          desc = "Remove SSH host" },
  { on = ["M","m"], run = "plugin sshfs -- mount --jump",    desc = "Mount & jump" },
  { on = ["M","u"], run = "plugin sshfs -- unmount",         desc = "Unmount SSHFS" },
  { on = ["g","m"], run = "plugin sshfs -- jump",            desc = "Jump to mount" },
]
```

Not required, but I would highly encourage adding this one too. This plugin pulls from your `ssh_config` so being able to quickly edit it is quite handy.

```toml
[mgr]
prepend_keymap = [
  { on = [
    "M",
    "c",
  ], run = "cd ~/.ssh/", desc = "Go to ssh config" },
]
```

## Usage

- **Mount (`M m``):** Choose a host and select a remote directory (`~` or `/`). This works for hosts from your`~/.ssh/config` and any custom hosts you've added.
- **Add host (`M a`):** Enter a custom host (`user@host`) to save it for future mounts.
- **Remove host (`M r`):** Select and remove any added custom hosts.
- **Jump to mount (`g m`):** Jump to any active mount from another tab or location.
- **Unmount (`M u`):** Choose an active mount to unmount it.

## Tips and Performance

- If key authentication fails, the plugin will prompt for a password up to 3 times before giving up.
- SSH keys vastly speed up repeated mounts (no password prompt), leverage your `ssh_config` rather than manually adding hosts to make this as easy as possible.
- You can edit the mount flags in `main.lua` to enable caching:

  ```lua
  sshfs ... -o cache=yes,cache_timeout=300,compression=no ...
  ```
