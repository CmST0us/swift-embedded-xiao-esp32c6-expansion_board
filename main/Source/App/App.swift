//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors.
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import U8g2Kit
import CU8g2
import Support

class ESP32C6U8g2Driver: Driver {
    init() {
        super.init(u8g2_Setup_ssd1306_128x64_noname_f, &U8g2Kit.u8g2_cb_r0)
    }
}

@_cdecl("app_main")
func main() {
    let driver = ESP32C6U8g2Driver()
    driver.withUnsafeU8g2 { u8g2 in
        u8g2_InitDisplay(u8g2)
        u8g2_SetFont(u8g2, Font().rawValue)
        u8g2_DrawStr(u8g2, 0, 10, "Hello World!")
        u8g2_SendBuffer(u8g2)
    }
}
