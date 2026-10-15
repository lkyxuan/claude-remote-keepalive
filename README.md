# claude-remote-keepalive

Keep [Claude Code Remote Control](https://code.claude.com/docs/en/remote-control) running on a Mac all the time, so you can start and steer Claude Code sessions on that machine from your phone or claude.ai/code whenever you want.

`claude remote-control` normally lives in a terminal window: close the window, log out or reboot, and your phone can no longer reach the machine. This script runs it in the background, starts it when you log in, restarts it if it exits, and keeps the Mac from idle-sleeping while it runs.

> 中文说明见下方 [中文](#中文)。

## Requirements

- macOS (uses `launchd`, `screen` and `caffeinate`, all built in)
- [Claude Code](https://code.claude.com) CLI installed and logged in with a Claude subscription

## Quick start

```bash
mkdir -p ~/bin && curl -fsSL https://raw.githubusercontent.com/lkyxuan/claude-remote-keepalive/main/claude-remote.sh -o ~/bin/claude-remote.sh
chmod +x ~/bin/claude-remote.sh

# Trust the folder once (Claude asks the first time Remote Control runs in a folder)
cd ~/my-project && claude      # answer "yes" to the trust prompt, then exit

# Start at login, in that folder
~/bin/claude-remote.sh install ~/my-project
~/bin/claude-remote.sh status
```

Then open the Claude mobile app or claude.ai/code. Your computer shows up under its computer name.

## Commands

| Command | What it does |
| --- | --- |
| `start [dir]` | Start in the background now |
| `stop` | Stop |
| `restart [dir]` | Restart |
| `status` | Show whether it is running and whether start-at-login is installed |
| `attach` | Show the Remote Control terminal UI (detach with `Ctrl-A` then `D`) |
| `log` | Follow the log (`~/Library/Logs/claude-remote/claude-remote.log`) |
| `install [dir]` | Start at login via a launchd agent, restart it if it exits |
| `uninstall` | Remove the launchd agent and stop |

`dir` defaults to `$HOME`.

## Options

Set these as environment variables, e.g. `CLAUDE_RC_PERM=auto ~/bin/claude-remote.sh install ~/my-project`. `install` saves them into the launchd agent.

| Variable | Default | Meaning |
| --- | --- | --- |
| `CLAUDE_RC_DIR` | `$HOME` | Working directory (if not passed as an argument) |
| `CLAUDE_RC_NAME` | computer name | Name shown in claude.ai/code and the app |
| `CLAUDE_RC_PERM` | unset | Permission mode for spawned sessions: `default`, `acceptEdits`, `auto`, `plan`, `dontAsk`, `bypassPermissions`. Unset uses your own Claude Code settings |
| `CLAUDE_RC_SPAWN` | `same-dir` | `same-dir`, `worktree` or `session` (see `claude remote-control --help`) |
| `CLAUDE_RC_AUTO_TRUST` | `0` | `1` answers the folder-trust prompt with "y" automatically |

## Things to know

- **Folder trust.** The first time Remote Control runs in a folder, Claude asks whether you trust it. Without a terminal nobody can answer, so trust the folder once by running `claude` there. `CLAUDE_RC_AUTO_TRUST=1` answers it for you, but that skips a security check on purpose built into Claude Code, so only use it for folders you know.
- **Permissions.** With `CLAUDE_RC_PERM=bypassPermissions`, anything you type on your phone runs on your computer without confirmation. Point it at a folder you are comfortable with.
- **Sleep.** `caffeinate -i` stops idle sleep. A laptop with its lid closed still sleeps. On a desktop Mac, also consider *System Settings → Energy → Prevent automatic sleeping when the display is off*.
- **Login, not boot.** launchd agents start when you log in. Turn on automatic login if you want it up right after a reboot.
- **Claude desktop app.** If the Claude desktop app already serves the same folder over Remote Control, the CLI refuses to start there ("This folder is already served by the Claude app"). Use a different folder, or turn Remote Control off for that folder in the app.
- Only one instance is managed at a time.

## How it works

- `launchd` runs the script at login and restarts it when it exits (`KeepAlive`, 30s throttle).
- `claude remote-control` needs a terminal, so it runs inside a `screen` session, which also lets you `attach` to it.
- macOS ships `screen` 4.0, which has no `-Logfile`, so the log path is set in a small screenrc.
- `screen -ls` exits 1 on macOS even when sessions exist; the script avoids treating that as "not running".

## Uninstall

```bash
~/bin/claude-remote.sh uninstall
rm ~/bin/claude-remote.sh
rm -rf ~/Library/Logs/claude-remote
```

---

## 中文

让 Mac 上的 Claude Code Remote Control 一直开着:登录后自动启动、退出后自动重启、运行时防止空闲睡眠。这样你随时可以在手机或 claude.ai/code 上操控这台电脑上的 Claude Code。

```bash
mkdir -p ~/bin && curl -fsSL https://raw.githubusercontent.com/lkyxuan/claude-remote-keepalive/main/claude-remote.sh -o ~/bin/claude-remote.sh
chmod +x ~/bin/claude-remote.sh

cd ~/my-project && claude      # 第一次先信任这个文件夹,然后退出
~/bin/claude-remote.sh install ~/my-project
~/bin/claude-remote.sh status
```

- 想全自动不弹确认:安装时加 `CLAUDE_RC_PERM=bypassPermissions`(手机上的指令会直接在电脑上执行,请注意)。
- 想让它自动回答"信任文件夹"的提示:加 `CLAUDE_RC_AUTO_TRUST=1`。
- 如果 Claude 桌面 app 已经在同一个文件夹上开着 Remote Control,脚本会启动失败,换一个文件夹即可。

## License

MIT
