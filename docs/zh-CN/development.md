# 开发

[中文](development.md) | [English](../development.md)

## 目录结构

```
metadata.lua                  插件名、版本、备注和主页
hooks/available.lua           vfox search：版本及其名字
hooks/pre_install.lua         vfox install：按给出的名字返回下载信息
hooks/post_install.lua        解压之后无需做任何事
hooks/env_keys.lua            PATH，使 zig 可以运行
hooks/pre_use.lua             vfox use：名字指向的已安装版本
hooks/detect.lua              vfox link --detect：机器上已有的 zig
lib/util.lua                  索引、名字、排序和平台
lib/detect_zig.lua            通过可执行文件和 lib/std 找到 zig 的安装
tests/*_test.lua              离线的 hook 测试，由 vfox plugin test 运行
tests/fixtures/index/         测试应答所用的两个索引的副本
tests/e2e/                    端到端检查，一个同时用于 Linux 和 Windows 的 Go 测试
tests/e2e/linux/Dockerfile    在容器中于 Linux 上运行它们的镜像
Injection.lua                 vfox 注入对象的类型提示，从不加载
stylua.toml、.luarc.json      格式化，以及 Lua 语言服务器的设置
.licenserc.yaml               许可证头
opencode.jsonc                让本仓库中的 OpenCode 代理会话无需询问即可执行 git push、gh pr create 和 gh pr comment
README.md、docs/              文档；README_CN.md 和 docs/zh-CN/ 是中文版本
```

vfox 加载 `metadata.lua`，在命令需要时调用对应的 hook，并把 `PLUGIN` 和 `RUNTIME`（`osType`、`archType`、`version`）放入作用域。`osType` 和 `archType` 是 vfox 二进制的 GOOS 和 GOARCH；macOS 上 `osType` 是 `darwin`（索引里叫 `macos`）。

## 每条命令调用哪些 hook

| 你运行 | 调用的 hook |
| --- | --- |
| `vfox search zig` | `Available` |
| `vfox install zig@latest` | `PreInstall` 返回下载地址、名字和 SHA-256。vfox 下载、校验、解压，然后调用 `PostInstall` |
| `vfox use zig@latest` | `PreUse` 返回要选中的已安装名字。`EnvKeys` 提供 `PATH` |
| `vfox link --detect zig` | `Detect` 返回机器上已有的 zig 安装（`lib/detect_zig.lua`） |
| `vfox info zig` | `metadata.lua` 中的备注 |

## 与 vfox 的约定

这些是 hook 依赖的约定，测试会检查它们。

- `Available` 返回 `{ version, note }` 的列表，vfox 把第一项当作 `zig@latest` 的版本。因此顺序是：正式版在前，从新到旧；然后是开发版，从新到旧（`util:releases()`）。
- 备注是构建的名字，用 `, ` 分隔。最新的正式版带有 `latest`。`PreInstall` 和 `PreUse` 先按版本号匹配名字，再按备注中的名字匹配。
- `PreInstall` 返回 `url`、`version`、`sha256` 和 `note`。版本号就是安装的名字。vfox 用 `sha256` 校验下载，它必须是索引给出的小写十六进制摘要。
- Mach 构建可以有两个地址。`util.download_url` 只对第一个地址发一次 HEAD 请求，只有它没有返回 200 时才回退到第二个。正式版只有一个地址，因此不发请求。
- `PreUse` 返回表或 `nil`，绝不返回裸字符串（vfox 1.0.12 之后会拒绝字符串）。已安装的名字、裸的或带点的数字返回 `nil`，因此 `use` 对它们不读取索引。
- `Detect` 返回 `{ version, path, note }`。`version` 必须是 vfox 接受的名字（字母、数字和 `._+-`），`path` 是存放 zig 可执行文件的目录。
- `EnvKeys` 把安装目录放入 `PATH`。zig 在可执行文件旁边找自己的库，因此不需要设置其它变量。

## 测试

离线的 hook 测试在 `vfox plugin test` 下运行，vfox 1.0.13 及之后的版本带有此命令。它会找到每个 `tests/**/*_test.lua`，并且每个文件在独立的虚拟机中运行，因此新增测试文件无需在任何地方登记：

```bash
vfox plugin test .
vfox plugin test . --file tests/available_test.lua
```

请在仓库根目录运行。Test Plugin 工作流安装 `.github/workflows/test.yml` 中固定的版本。

测试文件调用一次 `vfox.test` 中的 `test.load()`，然后通过它返回的插件调用 hook，例如 `plugin:PreInstall({ version = "0.13.0" })`。`test.load` 接受平台（`os`、`arch`）、环境变量（`env`），以及回答每个 HTTP 请求的函数（`http`，它接收 `request.url` 和 `request.method`，返回 `{ status_code, body }` 或 `nil, err`）。`lib` 中的模块可以在它之后 require。`RUNTIME.osType` 和 `RUNTIME.archType` 可以修改，以模拟其它平台。

测试用 `tests/fixtures/index` 中的索引副本作答，因此检查的是 2026 年 11 月 21 日索引中真实的内容，并且不需要网络。刷新方法见 `tests/fixtures/index/README.md`。`detect_test.lua` 和 `detect_windows_test.lua` 用一张表替换 `io.open` 和 `io.popen`，检查哪些目录会被报告。

## Lint 与格式

以下内容都在 CI 中运行（`.github/workflows/lint.yml`、`license.yml`），版本即工作流中固定的版本。

```bash
stylua --check .                      # StyLua 2.5.2，使用 stylua.toml
lua-language-server --check . --checklevel=Warning   # LuaLS 3.19.1，使用 .luarc.json
gofmt -l tests/e2e                    # Go：无输出表示格式正确
(cd tests/e2e && go vet ./... && GOOS=windows go vet ./...)   # Go：vet，同时检查 Linux 和 Windows
hadolint < tests/e2e/linux/Dockerfile
actionlint                            # 工作流
```

Go 代码由 `gofmt` 和 `go vet` 检查；`GOOS=windows go vet` 同时编译测试的 Windows 版本。

## 许可证头

每个源文件开头都有 `.licenserc.yaml` 中的 Apache 2.0 许可证头。`apache/skywalking-eyes` 检查它（`header check`），`header fix` 为缺少它的文件补上。Markdown 和 JSON 不检查。

## 编写文档

英文页面在 `docs/` 中，中文页面在 `docs/zh-CN/` 中，文件名相同；中文 README 是 `README_CN.md`。每个页面开头都链接到另一种语言。新页面要加入两个 README 的文档列表。引用索引数据的页面需注明数据的日期。

## 更新日志

`docs/changes.md` 和 `docs/zh-CN/changes.md` 描述对用户可见的变化。行为变化、修复或新增的 hook 都要在两种语言中列出，放在文件顶部的 `## Unreleased`（未发布）标题下；发布时，该标题改为版本号（见 [发布之后](#发布之后)）。

## 发布

维护者在默认分支上进入 **Actions → Plugin → Run workflow**，输入不带 `v` 前缀的稳定插件版本号来发布。共享工作流 [plugin-manifest-action](https://github.com/version-fox/plugin-manifest-action) 会更新 `metadata.lua`、创建版本提交和标签，并在本仓库发布 ZIP 与 manifest。不需要本地标签，也不需要额外的发布令牌。拉取请求只运行检查。

当 `PLUGIN.version` 与标签一致时，推送版本标签也会发布。发布失败时，重新运行失败的任务即可继续。工作流跟随共享的 `@v1` 发布工具，更新工具不会发布本插件。

### 发布之后

文档用 "未发布"（英文为 Unreleased）标记比上一个发布更新的内容。发布之后：

1. 把这些条目移到 [changes.md](changes.md) 中新版本的标题下（中英文都要改），标题写上发布日期（如 `## 0.1.2（2026-11-21）`），并删去 `Unreleased` / `未发布` 标题。`grep -rn -i -e unreleased -e 未发布 docs README*` 用来查找仍有标记的地方；移动之后，只有这两个页面中的说明会匹配。
2. 刷新 `tests/fixtures/index/README.md` 中索引副本的日期时，同步检查 [versions.md](versions.md) 中的示例。
