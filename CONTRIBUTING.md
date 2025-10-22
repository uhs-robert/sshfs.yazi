# Contributing to sshfs.yazi

Thanks for your interest in contributing! Community feedback and support are always welcome. This is a free and open-source plugin.

---

## 🐛 Reporting Bugs

- Check if an issue already exists.
- Open a [GitHub Issue](../../issues) with:
  - What happened?
  - What did you expect to happen?
  - Your OS, Yazi version, SSHFS version, and any relevant SSH config.
  - Log output or screenshots if available.

---

## 💡 Suggesting Features

- Use [Discussions](../../discussions) → **Ideas** to propose improvements or brainstorm.
- If it’s well-formed and actionable, feel free to open a feature request issue.

---

## 🧪 Running and Testing

1. Follow the installation instructions in the [README](./README.md).
2. Open `~/.config/yazi/plugins/sshfs.yazi/main.lua` and set `isDebugEnabled = true` near the top of the file.
3. Debug logs will be written to: `~/.local/state/yazi/sshfs.log`
4. You can directly edit `main.lua` to test changes. Just close and reopen Yazi to reload them.
5. Please test against a variety of SSH setups if possible (key-based, password, root, etc).

---

## 🧼 Style Guide

- Keep it minimal and readable.
- Lua syntax (used by Yazi plugins).
- Prefer local functions and clear naming.
- Avoid external dependencies unless necessary.

---

## 🛂 License

By submitting a pull request, you agree to license your contribution under the same terms as the project's license.
