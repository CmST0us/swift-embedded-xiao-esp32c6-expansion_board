# Swift for Embedded Systems + ESP-IDF: `.got.plt` 被丢弃问题修复

## 问题描述

在使用 Swift for Embedded Systems 编译 ESP32C6 项目时，链接阶段报错：

```
/home/eki/espidf/idf-5.5.1/tools/riscv32-esp-elf/esp-14.2.0_20241119/riscv32-esp-elf/bin/ld: discarded output section: `.got.plt'
/home/eki/espidf/idf-5.5.1/tools/riscv32-esp-elf/esp-14.2.0_20241119/riscv32-esp-elf/bin/ld: final link failed
collect2: error: ld returned 1 exit status
```

## 根因分析

### 1. Swift/LLVM 生成 PIC 重定位

Swift 编译器（通过 LLVM）在编译 RISC-V 目标时，即使指定了 `-fno-pic -fno-pie`，仍可能生成需要 **Procedure Linkage Table (PLT)** 和 **Global Offset Table (GOT)** 的重定位类型：

- `R_RISCV_CALL_PLT`：函数调用通过 PLT
- `R_RISCV_GOT_HI20`：全局变量访问通过 GOT

这些重定位要求链接器生成 `.got` 和 `.got.plt` 段来存储运行时地址。

### 2. ESP-IDF Linker Script 显式丢弃

ESP-IDF 5.5.x 生成的 `sections.ld` 在末尾包含一个 `/DISCARD/` 块：

```ld
/DISCARD/ :
{
  *(.rela.*)
  *(.got .got.plt) /* TODO: GCC-382 */
  *(.eh_frame_hdr)
  *(.eh_frame)
}
```

这个设计是为了：
- 嵌入式系统通常不需要 PIC/PIE 的运行时重定位
- 减少最终二进制大小
- 避免在 bare-metal 环境中使用动态链接机制

### 3. 链接器行为

GNU `ld` 的处理顺序：
1. 收集所有输入对象中的 `.got.plt` 段
2. 尝试创建输出段 `.got.plt`
3. 发现 `sections.ld` 的 `/DISCARD/` 块匹配 `*(.got .got.plt)`
4. 报错：`discarded output section: '.got.plt'`

**关键点**：问题不在链接器本身（g++/ld vs swiftc/ld.lld），而在 **linker script 的丢弃规则**。即使换成 Swift 的 `ld.lld`，只要使用同一个 `sections.ld`，仍然会丢弃。

## 解决思路

### 方案对比

| 方案 | 优点 | 缺点 | 可行性 |
|------|------|------|--------|
| **禁用 PIC/PIE** | 从源头消除 `.got.plt` | Swift/LLVM 可能仍生成 PLT 重定位 | ❌ 不可行 |
| **自定义 linker script** | 完全控制段布局 | 需要维护整个脚本 | ⚠️ 复杂，易与 ESP-IDF 更新冲突 |
| **修改 ESP-IDF 源码** | 永久解决 | 需要 fork ESP-IDF，维护成本高 | ⚠️ 不推荐 |
| **构建时 patch `sections.ld`** | 最小侵入，自动应用 | 需要确保 patch 时机正确 | ✅ **推荐** |

### 最终方案：构建时 Patch Linker Script

**核心思路**：在 `/DISCARD/` 块**之前**插入显式的 `.got` 和 `.got.plt` 输出段，让链接器先收集这些段到 `sram_seg`，这样 `/DISCARD/` 就匹配不到它们了。

**为什么有效**：
- Linker script 的匹配是**顺序的**：先匹配的输出段定义会“消费”输入段
- 一旦 `.got.plt` 被前面的 `.got.plt : { *(.got.plt) }` 收集，`/DISCARD/` 中的 `*(.got .got.plt)` 就匹配不到任何内容
- 不会产生冲突，因为每个输入段只会被第一个匹配的输出段定义使用

## Patch 实现细节

### 1. Patch 脚本：`main/patch_sections_ld.cmake`

```cmake
# 查找 /DISCARD/ 块的位置
set(_needle "\n  /DISCARD/ :")
string(FIND "${_content}" "${_needle}" _pos)

# 在 /DISCARD/ 之前插入 .got/.got.plt 段定义
set(_insertion "\n  /* swift_got_fix */\n  .got :\n  {\n    *(.got)\n    *(.got.*)\n    *(.igot)\n    *(.igot.*)\n  } > sram_seg\n\n  .got.plt :\n  {\n    *(.got.plt)\n    *(.got.plt.*)\n    *(.igot.plt)\n    *(.igot.plt.*)\n  } > sram_seg\n")

string(REPLACE "${_needle}" "${_insertion}${_needle}" _patched "${_content}")
```

**关键特性**：
- **幂等性检查**：通过查找 `/* swift_got_fix */` 标记，避免重复 patch
- **容错处理**：如果 `sections.ld` 尚未生成，静默跳过（CMake 的 `DEPENDS` 确保 patch 在文件生成后执行）
- **完整匹配**：包含 `.got.*`、`.igot`、`.igot.*` 等变体，确保所有相关段都被收集

### 2. CMake 集成：`main/CMakeLists.txt`

```cmake
# 获取生成的 sections.ld 路径（ESP-IDF 的 ldgen 工具会从 sections.ld.in 生成）
idf_build_get_property(_build_dir BUILD_DIR)
set(_sections_ld "${_build_dir}/esp-idf/esp_system/ld/sections.ld")

# 创建 custom command，依赖于 sections.ld 文件
# 使用 stamp 文件确保每次构建只执行一次 patch
set(_patch_stamp "${_build_dir}/esp-idf/main/swift_patch_sections_ld.stamp")
add_custom_command(
    OUTPUT "${_patch_stamp}"
    COMMAND "${CMAKE_COMMAND}" -DSECTIONS_LD=${_sections_ld} -P "${CMAKE_CURRENT_LIST_DIR}/patch_sections_ld.cmake"
    COMMAND "${CMAKE_COMMAND}" -E touch "${_patch_stamp}"
    DEPENDS "${_sections_ld}"
    COMMENT "Patching sections.ld to keep .got/.got.plt"
    VERBATIM
)

# 创建 ALL target 触发 patch，确保每次构建都执行
add_custom_target(swift_patch_sections_ld ALL DEPENDS "${_patch_stamp}")
```

**为什么 patch `.ld` 文件而不是 `.in` 文件**：
- **关键发现**：ESP-IDF 的 `ldgen` 工具在构建时会从 `sections.ld.in` **重新生成** `sections.ld`
- 如果 patch `.in` 文件，生成的 `.ld` 会覆盖我们的修改
- 因此必须 patch **生成的** `sections.ld` 文件，在 `ldgen` 生成之后、链接器读取之前
- 使用 `DEPENDS "${_sections_ld}"` 确保 patch 在 `sections.ld` 生成后执行
- 使用 stamp 文件避免重复执行，同时让构建系统正确跟踪依赖关系

### 3. Patch 效果

**Patch 前**（`sections.ld` 末尾）：
```ld
  .riscv.attributes 0: { *(.riscv.attributes) }

  /DISCARD/ :
  {
   *(.rela.*)
   *(.got .got.plt) /* TODO: GCC-382 */
   *(.eh_frame_hdr)
   *(.eh_frame)
  }
}
```

**Patch 后**：
```ld
  .riscv.attributes 0: { *(.riscv.attributes) }
  /* swift_got_fix */
  .got :
  {
    *(.got)
    *(.got.*)
    *(.igot)
    *(.igot.*)
  } > sram_seg

  .got.plt :
  {
    *(.got.plt)
    *(.got.plt.*)
    *(.igot.plt)
    *(.igot.plt.*)
  } > sram_seg

  /DISCARD/ :
  {
   *(.rela.*)
   *(.got .got.plt) /* TODO: GCC-382 */
   *(.eh_frame_hdr)
   *(.eh_frame)
  }
}
```

**结果**：
- `.got` 和 `.got.plt` 被收集到 `sram_seg`（SRAM 段）
- `/DISCARD/` 中的 `*(.got .got.plt)` 匹配不到任何内容（已被前面的定义消费）
- 链接成功，不再报 `discarded output section` 错误

## 验证

构建日志中应看到：
```
-- Patched sections.ld to keep .got/.got.plt: /path/to/build/esp-idf/esp_system/ld/sections.ld
```

最终链接应成功：
```
[11/13] Linking CXX executable main.elf
[12/13] Generating binary image from built executable
Successfully created esp32c6 image.
```

## 注意事项

1. **内存占用**：`.got` 和 `.got.plt` 会占用 SRAM，但通常很小（几 KB）
2. **ESP-IDF 更新**：如果 ESP-IDF 更新后 `sections.ld` 的 `/DISCARD/` 块格式变化，可能需要调整 patch 脚本的匹配模式
3. **其他工具链**：此方案适用于任何生成 `.got.plt` 的工具链（不仅是 Swift）
4. **Patch 时机**：Patch 在 `sections.ld` 生成后、链接前执行，通过 CMake 的 `DEPENDS` 机制确保顺序正确

## 相关文件

- `main/patch_sections_ld.cmake`：Patch 脚本
- `main/CMakeLists.txt`：CMake 集成（第 186-214 行）
- `build/esp-idf/esp_system/ld/sections.ld`：ESP-IDF 生成的 linker script（会被 patch 修改）
- `build/esp-idf/main/swift_patch_sections_ld.stamp`：Patch 执行标记文件（用于依赖跟踪）

## 参考

- [ESP-IDF Linker Script Generation](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/linker-script-generation.html)
- [GNU LD Linker Scripts](https://sourceware.org/binutils/docs/ld/Scripts.html)
- [RISC-V Relocations](https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/master/riscv-elf.adoc#relocations)

