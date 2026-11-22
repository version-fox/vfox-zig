# 端到端检查

[中文](e2e.md) | [English](../e2e.md)

离线的 hook 测试和 lint 在 Test Plugin 与 Lint 工作流中运行。端到端检查把插件装进真正的 vfox，并针对真实的索引运行，覆盖 Linux 和 Windows。它们是 `tests/e2e` 中的一个 Go 测试，两个系统上运行相同的检查。

## Linux

在一次性的容器中运行，需要 Docker。在仓库根目录执行：

```bash
docker build -t zig-e2e tests/e2e/linux
docker run --rm -v "$PWD:/src:ro" zig-e2e
```

镜像是 `golang:1.27.1` 加上 vfox 1.1.0，构建镜像时会检查 vfox 的 SHA-256，并带有解压系统副本所需的 xz。代码目录以只读方式挂载，运行不会改动它；每次运行都有自己的 vfox 主目录和 zig 缓存目录。

在 Linux 主机上运行时，需要 `PATH` 中有 vfox 1.1.0 或更新的版本、Go，以及支持 xz 的 `tar`：

```bash
cd tests/e2e
go test -v -count=1 -run TestE2E .
```

CI 在 E2E 工作流中于 `ubuntu-latest` 上运行它。

## Windows

同一个测试原生运行，不需要 Docker。需要 `PATH` 中有 vfox 1.1.0 或更新的版本、Go 和 PowerShell 7：

```powershell
cd tests/e2e
go test -v -count=1 -run TestE2E .
```

CI 在 `windows-latest` 上运行它。工作目录的名字里有空格，因为 Windows 的临时目录路径常常带有空格。

## 检查什么

测试把以下检查作为子测试按此顺序运行，遇到第一个失败就停止：

1. vfox 是 1.1.0 或更新的版本，并且会读取标准错误：不带参数的 `vfox link` 把用法写到标准错误。从本仓库添加插件（`vfox add zig --source`），`vfox info zig` 指向列出名字的 README。
2. `vfox search zig` 列出 `0.13.0`、`nightly` 备注、一个 Mach 构建的名字，以及 `latest` 备注。
3. `vfox install zig@0.13.0` 按校验和校验下载（打印 `Verifying checksum`），之后 `zig` 报告 `0.13.0`。
4. 标准库能从已安装的 zig 中找到：一个用 `std.debug.print` 输出的程序可以编译并运行。
5. `vfox install zig@latest` 安装搜索列表标为 `latest` 的那个正式版，`vfox use` 选中的 `zig@latest` 也是它。这一项检查 `latest` 确实是最新的正式版，而不是最新的 nightly。
6. `vfox install zig@2024.11.0-mach` 按名字安装 Mach 构建，`vfox use` 能选中它。这个构建已经不在 ziglang.org 上（2026 年 11 月 22 日检查），它的下载来自索引为 Mach 软件包站点列出的地址。
7. `vfox install zig@9.9.9` 失败，并且消息中写出了它查找的平台。
8. vfox 没有安装的 zig 通过 `vfox link --detect -y zig` 链接。运行期间该副本位于 `PATH` 中。列表中显示链接，`vfox use` 选中链接的 zig，第二次 `link --detect` 没有发现新内容，`vfox uninstall` 删除链接并保留副本。

在 Linux 和 macOS 上，未设置 shell hook 时 vfox 不会改变版本，卸载时若要切换到另一个版本也需要 hook。因此检查中的每条 vfox 命令都在执行过 `vfox activate` 的 shell 中运行：Linux 上是 bash，Windows 上是 PowerShell 7。运行 zig 的检查会先应用全局 zig 的环境，与 shell hook 在两次提示之间的做法一致。

## 网络使用

每次运行下载约 200 MB：来自 ziglang.org 和 machengine.org 的索引；zig 0.13.0、最新的正式版、Mach 构建（来自 ziglang.org，或 Mach 的软件包站点）；以及作为系统副本的 zig 0.12.1（来自 ziglang.org）。在 CI 中，vfox 本身从 GitHub 下载。

vfox 命令的输出报告超时时会再次运行，共最多三次，因为索引和下载都经过网络。其它失败会立即停止运行。

## 未覆盖的范围

- macOS 和 arm64 主机没有端到端运行。它们由离线测试（用于设置平台）和 `docs/versions.md` 中的索引查找覆盖。
- Windows 的检查在 CI 和 Windows 主机上运行。本地用 `GOOS=windows go vet` 编译了测试的 Windows 版本。
