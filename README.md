# sshfs.yazi

> A minimal, fast **SSHFS** integration for the [Yazi](https://github.com/sxyazi/yazi) terminal file‑manager.
> Mount any host from your `.ssh/config` or add custom ones to yazi. Browse / edit / delete from remote hosts as if the files were local, jump back with a keystroke

<!--toc:start-->

- [sshfs.yazi](#sshfs.yazi)
  - [Preview](#preview)
  - [Why SSHFS](#why-sshfs)
  - [What It Does Under the Hood](#what-it-does-under-the-hood)
  - [Features](#features)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Key Mapping](#key-mapping)
  - [Usage](#usage)
  - [Tips](#tips-performance)
  - [License](#license)
  <!--toc:end-->

---

## Preview

```text
M m  → mount a host from your ~/.ssh/config, then jump into it
M u  → unmount an active mount
g m  → jump to an active mount
M a  → add a new custom SSH host to yazi (not saved to your ~/.ssh/config)
M r  → remove a custom SSH host from yazi
```

_(TODO: Drop a short GIF or mp4 demo in `assets/`.)_

---

## Why SSHFS?

- **Works anywhere you have SSH access.** No VPN, NFS or Samba needed – only port 22.
- **Treat remote files like local ones.** Run `vim`, `nvim`, `sed`, preview images / videos directly, etc.
- **User‑space, unprivileged.** No root required; mounts live under `~/.cache/sshfs`.
- **Bandwidth‑friendly.** SSH compression and reconnect options are enabled by default.
- **Quick Loading and Operations.** SSHFS is fast; load / edit files quickly without lag including all additional functionality from yazi.

Perfect for tweaking configs, deploying sites, inspecting logs, or grabbing / editing / deleting files. SSHFS is fast, seamless, and native to your terminal.

---

## What it does under the hood

Basically, just a fancy wrapper for SSHFS that integrates it with Yazi. Reads hosts from your `ssh_config` to choose from. Maintains an optional separate list for yazi hosts as well. The sshfs function used is below:

```sh
sshfs user@host: ~/.cache/sshfs/alias -o reconnect,compression=yes,ServerAliveInterval=15,ServerAliveCountMax=3
```

## Features

- **One‑key mounting** – remembers your SSH hosts and reads from your `ssh_config`.
- **Jump/Return workflow** – quickly copy files between local & remote.
- Uses `sshfs` directly.
- Mount‑points live under `~/.cache/sshfs`, keeping them isolated from your regular file hierarchy.

---

## Requirements

| Software   | Minimum       | Notes                               |
| ---------- | ------------- | ----------------------------------- |
| Yazi       | `>=25.5.31`   | tested on 25.6+                     |
| sshfs      | any           | `sudo dnf/apt/pacman install sshfs` |
| fusermount | from FUSE     | usually pre-installed               |
| SSH config | working hosts | hosts come from `~/.ssh/config`     |

> [!NOTE]
>
> **This plugin only supports Linux**
>
> Sorry team, I don't use Mac or Windows! But I am open to a pull request that adds this support! To adapt for macOS or BSD, you'd need to modify the `remove_mountpoint()` logic in `main.lua` to use the appropriate `umount` or `diskutil` commands for your platform. Happy to help explain any of the code if you're up to the challenge!

---

## Installation

```sh
# via Yazi’s package manager
ya pack -a uhs-robert/sshfs
```

Modify your `~/.config/yazi/init.lua` to include:

```lua
require("sshfs"):setup()
```

---

## Key Mapping

Add this to your `~/.config/yazi/keymap.toml`:

Feel free to change the main modifier (`M`) or any of the other key map letters. You're the boss here!

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

---

## Usage

1. **Mount** – press `M m`, choose the host to mount. You'll then be prompted to select whether to land in the home directory `~` or root `/`. This includes both hosts from your `ssh_config` and any manually added hosts.
2. **Add** – press `M a`, enter a manual custom host (e.g. `username@example.domain.com`) to save for mount. Manual hosts must be valid SSH targets like `user@host`. These hosts are not stored in your `ssh_config` and are instead kept separately in `~/.config/yazi/plugins/sshfs/sshfs.list`.
3. **Remove** – press `M r`, select a manually added custom host to remove. This removes the host from `~/.config/yazi/plugins/sshfs/sshfs.list`.
4. **Jump** – Yazi automatically `cd`s into a mounted directory.
5. **Return** – press `g m` to jump back to any active mount.
6. **Unmount** – press `M u`, choose the host to unmount.

---

## Tips & Performance

- If key authentication fails, the plugin will prompt for a password up to 3 times before giving up.
- SSH keys vastly speed up repeated mounts (no password prompt), leverage your `ssh_config` rather than manually adding hosts to make this as easy as possible.
- You can edit the mount flags in `main.lua` to enable caching:

  ```lua
  sshfs ... -o cache=yes,cache_timeout=300,compression=no ...
  ```

---

## License

MIT – see `LICENSE`.
