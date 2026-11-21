# 版本名字及其数据来源

[中文](versions.md) | [English](../versions.md)

本页说明每个名字是什么意思、插件从哪里取得版本列表，以及名字不存在时会怎样。示例来自 2026 年 11 月 21 日的索引（[tests/fixtures/index/README.md](../../tests/fixtures/index/README.md)）。

## 版本列表从哪里来

插件读取两个索引：

| 索引 | 地址 | 是否必需 |
| --- | --- | --- |
| Zig 官方的 | https://ziglang.org/download/index.json | 是：正式版和 `master`（每日构建） |
| Mach 的 | https://machengine.org/zig/index.json | 否：Mach 项目命名的构建 |

`vfox search zig` 和 `vfox install` 都会读取这两个索引；`vfox use` 只在名字既不是已安装的版本、也不是数字时才读取（见 [`vfox use`](#vfox-use)）。Mach 的索引是可选的：读不到时插件打印警告，只列出官方正式版，所以一个索引不可用不会让另一个也不能用。

## 名字

| 名字 | 示例 | 含义 |
| --- | --- | --- |
| 版本号 | `0.13.0`、`0.17.1` | 官方正式版 |
| 版本号 | `0.14.0-dev.2577+271452d22` | 开发版，`+` 后面是提交号 |
| `latest` | | 最新的正式版，也就是 `vfox search zig` 的第一行 |
| `nightly` | | ziglang.org 上 Zig 的 master 构建 |
| Mach 名字 | `2024.11.0-mach`、`mach-latest` | Mach 项目命名的开发版 |

名字需要完全匹配。版本总是以它自己的版本号安装，所以 `vfox install zig@latest` 会以 `0.17.1` 这个名字安装，`vfox list zig` 显示的也是这个名字。无论输入哪个名字，安装的名字都一样：`zig@nightly` 安装的是 `0.18.0-dev.1260+833623422`。

## 列表和排序

`vfox search zig` 先列正式版（从新到旧），再列开发版（从新到旧）。vfox 把第一行当作 `zig@latest` 的版本，所以这个顺序保证 `latest` 是最新的正式版，而不是最新的 nightly。

版本按语义化版本比较：`0.17.1` 比 `0.17.0` 新；开发版 `0.17.0-dev.2228+955228b68` 比它的正式版 `0.17.0` 旧。

每行的备注写出该构建的名字，多个名字用逗号分隔。同一个构建可以有多个名字，Mach 的构建就是这样：

```
0.17.1                     latest
0.18.0-dev.1260+833623422  nightly
0.18.0-dev.935+ead8f5a7a   2026.10.22-mach, mach-latest
```

## 下载地址与校验和

每个构建从索引为该平台给出的地址下载：

- Zig 的正式版和 nightly 从 ziglang.org 下载。
- Mach 构建下载索引里的 `zigTarball`（ziglang.org）。有些旧的开发版已经不在 ziglang.org 上，索引同时在 Mach 的软件包站点上列出了它们，地址是 `tarball`。对这类构建，`vfox install` 会先用 HEAD 请求询问 ziglang.org，请求失败时改从 Mach 的软件包站点安装。

每次下载都会按索引列出的 SHA-256 校验。vfox 会打印 `Verifying checksum`，压缩包不匹配时停止。Mach 构建的两个地址使用同一个校验和，所以无论从哪个地址下载，校验都成立。

## 名字不能用时

| 你看到的 | 原因 | 怎么办 |
| --- | --- | --- |
| `zig 9.9.9 is not listed for linux/amd64` | 索引里没有这个名字在你的平台上的构建 | 运行 `vfox search zig`；消息里写着平台 |
| `No version given` | 运行 `vfox install zig` 时没有给出名字 | 给出名字，例如 `zig@latest` |
| `WARNING: cannot download https://machengine.org/zig/index.json: ...; listing the official releases only` | 读不到 Mach 的索引 | 检查网络；官方正式版仍然可用 |
| `cannot download https://ziglang.org/download/index.json: ...` | 读不到 Zig 的索引，因此无法列出或安装任何版本 | 检查网络，以及 ziglang.org 能否访问 |

## `vfox use`

`vfox use` 用来选择已安装的版本。下面这些名字不需要网络：

- 已安装的版本号，例如 `zig@0.13.0`；以及裸的或带点的数字，例如 `zig@0.13`，由 vfox 在已安装的版本里自行匹配。

其它名字 `latest`、`nightly` 和 Mach 名字需要到索引里查询，所以 `vfox use` 对它们需要网络。它们指向的版本一旦安装，`vfox use` 就会选中它。在此之前，vfox 会报告该名字未安装，此时运行 `vfox install` 即可安装。

## 平台

插件按索引使用的名字查找每个平台。下表给出 vfox 的平台（操作系统和架构，使用 Go 的名字）以及按顺序尝试的索引名字：

| vfox 平台 | 索引中的名字 |
| --- | --- |
| linux/amd64 | `x86_64-linux` |
| linux/arm64 | `aarch64-linux` |
| linux/386 | `x86-linux`、`i386-linux` |
| linux/arm | `arm-linux`、`armv7a-linux` |
| linux/ppc | `powerpc-linux` |
| linux/ppc64le | `powerpc64le-linux` |
| linux/loong64 | `loongarch64-linux` |
| linux/riscv64 | `riscv64-linux` |
| linux/s390x | `s390x-linux` |
| darwin/amd64 | `x86_64-macos` |
| darwin/arm64 | `aarch64-macos` |
| windows/amd64 | `x86_64-windows` |
| windows/arm64 | `aarch64-windows` |
| windows/386 | `x86-windows`、`i386-windows` |

表中没有的平台按它自己的 Go 名字查找。与 Go 名字不同的索引名字定义在 `lib/util.lua` 的 `arch_names` 中，`tests/util_test.lua` 对它们做了检查。
