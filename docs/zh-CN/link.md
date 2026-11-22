# 使用机器上已有的 Zig

[中文](link.md) | [English](../link.md)

如果机器上已经装有 Zig（来自系统包管理器、Scoop、Homebrew、mise、asdf、zvm，或你自己解压的副本），`vfox link --detect zig` 会直接纳入它，而不是再下载一份。这个命令需要 vfox 1.1.0 或更新的版本（用 `vfox --version` 查看）。

```bash
vfox link --detect zig
```

vfox 会列出插件找到的安装，你选择要链接的。`vfox link --detect -y zig` 不询问，全部链接。之后 `vfox use zig@...` 照常工作：`vfox list zig` 会用路径标出已链接的版本，`vfox uninstall` 只删除链接，Zig 本身留在原处。

## 会找什么

- `PATH` 各目录里的 `zig`（Windows 上是 `zig.exe`），这包括 Homebrew、系统包，以及你自己设置的 `PATH` 条目。符号链接会被追踪到真正存放可执行文件的目录，所以链接到 `/usr/lib/zig/zig` 的 `/usr/bin/zig` 会被报告为 `/usr/lib/zig`。
- 版本管理器（Linux 和 macOS）：mise（`~/.local/share/mise/installs/zig`）、asdf（`~/.asdf/installs/zig`）和 zvm（`~/.zvm`）。它们为每个版本保存一个目录；mise 和 asdf 还会再往下查一层，因为它们可能在版本目录里再放一层文件夹。Windows 上同样查找 mise（`%USERPROFILE%\.local\share\mise\installs\zig`）和 zvm（`%USERPROFILE%\.zvm`）。
- Windows 上 Scoop 的应用（`%USERPROFILE%\scoop\apps\zig`）。
- 系统目录：Linux 和 macOS 上的 `/usr/local`、`/opt`、`/usr/lib`，以及 Windows 上的 `C:\Program Files\zig`。每个目录本身及其下一层子目录都会被查找，所以 `/opt/zig-linux-x86_64-0.12.1` 能被找到。

## 什么样的目录算作 Zig

同时满足下面三条的目录才会被报告：

- 里面有 `zig` 可执行文件（Windows 上是 `zig.exe`）；
- 标准库在它旁边，即 `lib/std/std.zig`。这是官方压缩包的目录结构，也是 vfox 链接时所要求的，这样 zig 通过 `PATH` 就能找到自己的库；
- `zig version` 能运行并打印版本号，这就是安装的名字（`0.13.0`，或开发版的 `0.14.0-dev.2577+271452d22`）。

下面这些会被跳过：

- vfox 自己的安装：它的主目录下的一切（设置了 `VFOX_HOME` 时为该目录，否则为 `.vfox` 目录），以及任何 `cache/zig/v-<版本>` 目录，那是 vfox 保存每个安装的位置，不论它是在哪个主目录中安装的；
- shim 目录，例如 `~/.asdf/shims`、`~/.local/share/mise/shims`，或 Chocolatey 的 `bin`。shim 运行的是管理器当前选中的版本，而不是旁边的那一个；
- `PATH` 中的相对路径条目；
- 已经安装或已经链接的版本，以及同一版本的第二份副本（保留先找到的那一个，而 `PATH` 排在最前）。

在 Windows 和 macOS 上，检查 vfox 自己的安装和 shim 目录时不区分字母大小写，因为这两个系统的文件系统默认不区分大小写。其它系统（包括 Linux）按写法逐字比较：`/srv/VFox/bin` 不在 `VFOX_HOME=/srv/vfox` 之内，因此其中的 Zig 会被报告。

缺少 `lib/std` 的副本会被跳过。zig 在那里找不到自己的库，链接它只会得到一个不能用的 `zig`。

## 手动链接

`--detect` 找不到的地方，可以手动链接。给出存放 `zig` 可执行文件的目录，且 `lib` 位于它旁边：

```bash
vfox link zig@0.12.1 /opt/zig-linux-x86_64-0.12.1
vfox use --global zig@0.12.1
```

## 删除链接

`vfox uninstall zig@0.12.1` 只删除链接，不删除其它内容。Zig 留在原处，安装它的包管理器或版本管理器仍然可以使用。
