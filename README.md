# sshfs.yazi

> A minimal, fast **SSHFS** integration for the [Yazi](https://github.com/sxyazi/yazi) terminal file‑manager.
> Mount any host you already reach with `ssh`, browse / edit / delete as if the files were local, jump back with a keystroke

<!--toc:start-->

- [sshfs.yazi](#sshfs.yazi)
  - [Preview](#preview)
  - [Features](#features)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Key Mapping](#key-mapping)
  - [Usage](#usage)
  - [Examples](#examples)
  - [Tips](#tips-performance)
  - [License](#license)
  <!--toc:end-->

---

## Preview

```text
M a  → add an SSH alias (Host from ~/.ssh/config)
M m  → mount alias with sshfs, jump into it
M u  → unmount (fusermount ‑u)
g m  → jump to an active mount
```

_(Drop a short GIF or mp4 demo in `assets/` if you like.)_

---

## Why SSHFS?

- **Works anywhere you have SSH access.** No VPN, NFS or Samba needed – only port 22.
- **Treat remote files like local ones.** Run `vim`, `nvim`, `sed`, preview images / videos directly, etc.
- **User‑space, unprivileged.** No root required; mounts live under `~/.cache/sshfs`.
- **Bandwidth‑friendly.** SSH compression and reconnect options are enabled by default.
- **Quick Loading and Operations.** SSHFS is fast; load / edit files quickly without lag including bulk operations from yazi.

If you often hop into servers to tweak configs, deploy sites, grab logs, copy media, or delete files then SSHFS provides the perfect middle‑ground between `scp` transfers and a heavyweight sync tool.

---

## Features

- **One‑key mounting** – remembers common SSH hosts.
- **Jump/Return workflow** – quickly copy files between local & remote.
- Uses `sshfs` directly.
- Mount‑points live under `~/.cache/sshfs`, isolated from the rest of the File System.

---

## Requirements

| Software   | Minimum       | Notes                               |
| ---------- | ------------- | ----------------------------------- |
| Yazi       | `>=25.5.31`   | tested on 25.6+                     |
| sshfs      | any           | `sudo dnf/apt/pacman install sshfs` |
| fusermount | from FUSE     | usually pre-installed               |
| SSH config | working hosts | aliases come from `~/.ssh/config`   |

> [!NOTE]
>
> **This plugin only supports Linux**
> macOS/BSD users can adapt by swapping the mount/unmount commands.

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

```toml
[mgr]
prepend_keymap = [
  { on = ["M","a"], run = "plugin sshfs -- add",             desc = "Add SSH alias" },
  { on = ["M","r"], run = "plugin sshfs -- remove",          desc = "Remove SSH alias" },
  { on = ["M","m"], run = "plugin sshfs -- mount --jump",    desc = "Mount & jump" },
  { on = ["M","u"], run = "plugin sshfs -- unmount",         desc = "Unmount SSHFS" },
  { on = ["g","m"], run = "plugin sshfs -- jump",            desc = "Jump to mount" },
]
```

Feel free to change the main modifier (`M`) or any of the other key map letters.

---

## Usage

1. **Add** – press `M a`, enter an alias from `~/.ssh/config` (e.g. `prod`). The alias is stored in `~/.config/yazi/plugins/sshfs/sshfs.list`.
2. **Mount** – press `M m`. If there’s only one alias it mounts immediately, otherwise pick from the list.
3. **Jump** – Yazi automatically `cd`s into the mount directory (`~/.cache/sshfs/ALIAS`).
4. **Return** – press `g m` to jump back to any active mount.
5. **Unmount** – press `M u`, choose the alias to unmount.

---

## Examples

### Command‑line equivalent

```sh
# what the plugin runs under the hood
sshfs prod: ~/.cache/sshfs/prod -o reconnect,compression=yes,allow_other -o nonempty &

# unmount manually
fusermount -u ~/.cache/sshfs/prod
```

### Multiple hosts workflow

1. Add `web`, `db`, `backup` via `M a`.
2. `M m` → choose `web`, Yazi jumps into `/home/user/.cache/sshfs/web`.
3. Copy a config file to local, edit, paste back.
4. `g m` → choose `db`, inspect logs.
5. `M u` → pick `backup` after finishing cleanup.

---

## Tips & Performance

- Edit the mount flags in `main.lua` to enable caching:

  ```lua
  sshfs ... -o cache=yes,cache_timeout=300,compression=no ...
  ```

- If you see _“Transport endpoint is not connected”_ simply unmount then mount again.
- SSH keys + agent vastly speed up repeated mounts (no password prompt).

---

## License

MIT – see `LICENSE`.
