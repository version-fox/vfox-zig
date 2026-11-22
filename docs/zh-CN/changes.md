# 更新日志

[中文](changes.md) | [English](../changes.md)

每个版本中对用户可见的变化。GitHub 的 release 页面列出了提交记录。

## 未发布

- 在 Linux 上，`vfox link --detect zig` 会列出目录名与 `VFOX_HOME` 只在大小写上不同的 Zig，例如 `VFOX_HOME` 为 `/srv/vfox` 时的 `/srv/VFox/bin`。以前它被当作 vfox 自己的安装而漏掉。Linux 的文件系统区分大小写，这两者是不同的目录。Windows 和 macOS（默认设置）的文件系统不区分大小写，比较仍然忽略大小写。见 [link.md](link.md)。

## 0.1.3（2026-11-22）

- `vfox link --detect zig` 不再列出 vfox 在自定义 `VFOX_HOME` 下安装的 Zig，也不列出 vfox 在其它主目录中安装的 Zig。以前它们会被当作机器上已有的 Zig。见 [link.md](link.md)。
- 读不到索引时的警告改为写到标准错误。以前它们写到标准输出，所以 `vfox search zig | head -1` 得到的第一行是关于 Mach 索引的警告。

## 0.1.2（2026-11-21）

- `vfox link --detect zig` 可以纳入机器上已经装好的 Zig：包括 `PATH` 中的、版本管理器（mise、asdf、zvm、Scoop）中的，以及系统目录中的。需要 vfox 1.1.0 或更新的版本。见 [link.md](link.md)。
- `vfox install zig@latest` 现在安装最新的正式版。以前它安装的是最新的 nightly：vfox 把 `vfox search zig` 的第一项当作 latest，而 nightly 排在最前面。现在正式版排在前面（从新到旧），开发版排在后面（从新到旧）。见 [versions.md](versions.md#列表和排序)。
- `vfox use zig@latest`、`zig@nightly` 和 Mach 名字会选中它们指向的已安装版本。以前 `use` 找不到它们。
- ziglang.org 已经没有的 Mach 构建（例如 `2024.11.0-mach`）会从 Mach 索引为它给出的地址安装。以前安装可能因下载地址为空而失败，而且所用的地址取决于索引的遍历顺序。
- `vfox search zig` 中每个构建只列一次，名字之间用逗号分隔，例如 `2026.10.22-mach, mach-latest`。以前备注可能写成 `nightly|2024.11.0-mach`，而且一个 Mach 构建可能带上 nightly 的名字。
- 版本按语义化版本排序：`0.17.0` 列在 `0.17.0-dev.2228+955228b68` 之上。以前后者排在前面。
- Mach 的索引是可选的。读不到时，`vfox search zig` 和 `vfox install` 会打印警告，并只使用官方正式版。以前一个索引不可用就会让所有命令失败。
- 读取索引失败时，错误信息会写出地址和原因。以前的消息是关于 nil 值的 Lua 错误。
- 平台：32 位 ARM（较旧的正式版中为 `armv7a`，较新的为 `arm`）、32 位 PowerPC、LoongArch 和 POWER 小端（`ppc64le`）现在按索引使用的名字查找。
- `vfox info zig` 指向 README，README 列出了名字和命令。
- 仓库新增了中英文文档、lint 与许可证检查、hook 的离线测试，以及 Linux 和 Windows 的端到端检查。

## 0.1.1

- 本仓库的第一个版本：基于 ziglang.org 的索引和 Mach 的索引，提供 `Available`、`PreInstall`、`PostInstall`、`PreUse` 和 `EnvKeys` 这些 hook。历史见 `git log`。
