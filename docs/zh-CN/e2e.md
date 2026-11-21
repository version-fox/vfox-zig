# 端到端检查

[中文](e2e.md) | [English](../e2e.md)

离线的 hook 测试和 lint 在 Test Plugin 与 Lint 工作流中运行。端到端检查把插件装进真正的 vfox，并针对真实的索引运行，覆盖 Linux 和 Windows。

## Linux

在一次性的容器中运行，需要 Docker。在仓库根目录执行：

```bash
docker build -t zig-e2e tests/e2e/linux
docker run --rm -v "$PWD:/src:ro" zig-e2e
```

镜像是 Ubuntu 26.04 加上 vfox 1.1.0，构建镜像时会检查 vfox 的 SHA-256。代码目录以只读方式挂载，运行不会改动它；每次运行都有自己的 vfox 主目录和 zig 缓存目录。

在 Linux 主机上运行时，需要 `PATH` 中有 vfox 1.1.0 或更新的版本，以及 `zip`、`curl`、`sha256sum`、支持 xz 的 `tar` 和 `awk`：

```bash
bash tests/e2e/linux/e2e.sh
```

CI 在 E2E 工作流中于 `ubuntu-latest` 上运行它。

## Windows

Windows 的检查在 CI 的 `windows-latest` 上运行，本地不用容器运行。它需要 `PATH` 中有 vfox 1.1.0 或更新的版本，以及 PowerShell 7：

```powershell
pwsh -NoProfile -File tests/e2e/windows/e2e.ps1
```

它们原生运行，不需要 Docker。工作目录的名字里有空格，因为 Windows 的临时目录路径常常带有空格。

## 检查什么

两个脚本执行相同的检查，顺序一致，遇到第一个失败就停止：

1. vfox 是 1.1.0 或更新的版本，并且从本仓库添加插件（`vfox add zig --source`）。`vfox info zig` 指向列出名字的 README。
2. `vfox search zig` 列出 `0.13.0`、`nightly` 备注、一个 Mach 构建的名字，以及 `latest` 备注。
3. `vfox install zig@0.13.0` 按校验和校验下载（打印 `Verifying checksum`），之后 `zig` 报告 `0.13.0`。
4. 标准库能从已安装的 zig 中找到：一个用 `std.debug.print` 输出的程序可以编译并运行。
5. `vfox install zig@latest` 安装搜索列表标为 `latest` 的那个正式版，`vfox use` 选中的 `zig@latest` 也是它。这一项检查 `latest` 确实是最新的正式版，而不是最新的 nightly。
6. `vfox install zig@2024.11.0-mach` 按名字安装 Mach 构建，`vfox use` 能选中它。这个构建已经不在 ziglang.org 上，它的下载来自索引为 Mach 软件包站点列出的地址。
7. `vfox install zig@9.9.9` 失败，并且消息中写出了它查找的平台。
8. vfox 没有安装的 zig 通过 `vfox link --detect -y zig` 链接。运行期间该副本位于 `PATH` 中。列表中显示链接，`vfox use` 选中链接的 zig，第二次 `link --detect` 没有发现新内容，`vfox uninstall` 删除链接并保留副本。

## 网络使用

每次运行下载约 200 MB：来自 ziglang.org 和 machengine.org 的索引；zig 0.13.0 和 0.17.1、Mach 构建（来自 ziglang.org，或 Mach 的软件包站点）；以及作为系统副本的 zig 0.12.1（来自 ziglang.org）。在 CI 中，vfox 本身从 GitHub 下载。

## 未覆盖的范围

- macOS 和 arm64 主机没有端到端运行。它们由离线测试（用于设置平台）和 `docs/versions.md` 中的索引查找覆盖。
- Windows 脚本只在 CI 中运行。本地用 PowerShell 解析器和 PSScriptAnalyzer 做了检查。
