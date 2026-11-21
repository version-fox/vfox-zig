# Index fixtures

Byte-for-byte copies of the two indexes the plugin reads, taken on 2026-11-21:

| File | Source | SHA-256 |
| --- | --- | --- |
| `ziglang.json` | https://ziglang.org/download/index.json | `b519a8be8869e325d9af833e4c071d0f3bc60214ad6e073c5a60bd1d2007946a` |
| `mach.json` | https://machengine.org/zig/index.json | `fe284c61f219bc869fbf6226fe649461ed1e7c976a64fed16677bd34d66a0241` |

The offline tests (`tests/available_test.lua`, `tests/pre_install_test.lua`,
`tests/pre_use_test.lua`) answer the plugin's HTTP requests from these files, so
they check the plugin against what the indexes really contain on that day. The
expectations in those tests (for example `latest` naming 0.17.1, and the Mach
build `2024.11.0-mach` having a download URL) were read from these files.

When the indexes change, do not edit these files by hand. Download them again,
update the table above, and adjust the expectations that the new data changes.
