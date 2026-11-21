# vfox-zig

[中文](README_CN.md) | [English](README.md)

vfox-zig 是 [vfox](https://vfox.lhan.me/) 的 [Zig](https://ziglang.org/) 插件。它可以安装 Zig 的正式版、每日构建（nightly），以及 [Mach](https://machengine.org/) 项目命名的开发版本。它还能直接纳入机器上已经装好的 Zig，不必再下载一份。

## 安装

先安装 vfox。`vfox link --detect zig` 需要 vfox 1.1.0 或更新的版本（用 `vfox --version` 查看）；其它命令在更早的版本上也能用。然后添加插件：

```bash
vfox add zig
```

## 使用

```bash
vfox search zig                  # 列出版本，以及每个版本的名字
vfox install zig@0.13.0          # 按版本号安装正式版
vfox install zig@latest          # 安装最新的正式版
vfox use --global zig@latest     # 让所有 shell 都使用这个已安装的版本
zig version
```

每次安装都会按 ziglang.org（或 Mach）索引里列出的 SHA-256 校验下载内容。插件需要能访问这些索引。

机器上已经装好的 Zig 可以链接进 vfox，而不必重新安装：

```bash
vfox link --detect zig           # 列出找到的安装，你选择要链接的
vfox link --detect -y zig        # 不询问，全部链接
```

详见 [docs/zh-CN/link.md](docs/zh-CN/link.md)。

## 版本名字

| 名字 | 安装的内容 |
| --- | --- |
| `0.13.0`、`0.17.1` 等 | 正式版，以它自己的版本号安装 |
| `latest` | 最新的正式版 |
| `nightly` | ziglang.org 上 Zig 的 master 构建，即最新的开发版 |
| `2024.11.0-mach`、`mach-latest` 等 | Mach 项目命名的开发版 |

`vfox search zig` 先列正式版（从新到旧），再列开发版（从新到旧）。每行的备注写出它的名字，例如 `latest`，或 `nightly, mach-latest`。细节和数据来源见 [docs/zh-CN/versions.md](docs/zh-CN/versions.md)。

## 平台

插件安装索引里为运行 vfox 的平台列出的构建。最新的正式版在 Linux 上列出 `x86_64`、`aarch64`、`x86`、`arm`、`riscv64`、`powerpc64le`、`s390x` 和 `loongarch64` 构建，在 macOS 上列出 `x86_64` 和 `aarch64`，在 Windows 上列出 `x86_64`、`aarch64` 和 `x86`。旧版本列出的平台较少。某个版本没有你所在平台的构建时，会提示它在该平台上未列出；查找时使用的名字见 [docs/zh-CN/versions.md](docs/zh-CN/versions.md#平台)。

## 文档

- [版本名字及其数据来源](docs/zh-CN/versions.md)
- [使用机器上已有的 Zig](docs/zh-CN/link.md)
- [更新日志](docs/zh-CN/changes.md)
- [开发](docs/zh-CN/development.md)
- [端到端检查](docs/zh-CN/e2e.md)

## 发布这个插件

维护者可以在默认分支上进入 **Actions → Plugin → Run workflow**，输入不带 `v` 前缀的稳定插件版本号来发布。共享工作流会更新 `metadata.lua`、创建版本提交和标签，并在本仓库发布 ZIP 与 manifest。不需要本地标签，也不需要额外的发布令牌。拉取请求只运行检查；PR 标题不再触发发布。

当 `PLUGIN.version` 与标签一致时，也可以直接推送版本标签来发布。发布失败时，重新运行失败的原任务即可继续。

工作流跟随共享的 `@v1` 发布工具版本；更新工具不会发布本插件。包的约定和首次上线要求见 [共享工作流文档](https://github.com/version-fox/plugin-manifest-action)。发布之后的步骤见 [docs/zh-CN/development.md](docs/zh-CN/development.md#发布之后)。

## 许可证

Apache License 2.0，见 [LICENSE](LICENSE)。
