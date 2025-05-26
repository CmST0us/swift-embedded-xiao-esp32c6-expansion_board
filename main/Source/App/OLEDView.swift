import U8g2Kit
import CU8g2
import Support

class ESP32C6U8g2Driver: Driver {
    // OLED的I2C地址
    private let OLED_ADDRESS: UInt8 = 0x78
    
    init() {
        super.init(u8g2_Setup_ssd1306_128x64_noname_f, &U8g2Kit.u8g2_cb_r0)
        i2c_init()

        // Mask use this, otherwise i2c_driver_install will not found
        let installHandler = i2c_driver_install
    }

    override func onByte(msg: UInt8, arg_int: UInt8, arg_ptr: UnsafeMutableRawPointer?) -> UInt8 {
        switch Int32(msg) {
        case U8X8_MSG_BYTE_INIT:
            // 初始化时不需要特殊处理
            return 0
            
        case U8X8_MSG_BYTE_SEND:
            // 发送数据
            if let ptr = arg_ptr {
                let data = UnsafeMutableBufferPointer<UInt8>(start: ptr.assumingMemoryBound(to: UInt8.self), count: Int(arg_int))
                let result = i2c_write_data(OLED_ADDRESS, data.baseAddress, data.count)
                return result ? 0 : 1
            }
            return 1
            
        case U8X8_MSG_BYTE_START_TRANSFER:
            // 开始传输
            return 0
            
        case U8X8_MSG_BYTE_END_TRANSFER:
            // 结束传输
            return 0
            
        default:
            return 0
        }
    }

    override func onGpioAndDelay(msg: UInt8, arg_int: UInt8, arg_ptr: UnsafeMutableRawPointer?) -> UInt8 {
        switch Int32(msg) {
        case U8X8_MSG_GPIO_AND_DELAY_INIT:
            // 初始化时不需要特殊处理
            return 0
            
        case U8X8_MSG_DELAY_MILLI:
            // 延时处理
            if arg_int > 0 {
                // 使用系统延时函数
                delay_ms(UInt32(arg_int))
            }
            return 0
            
        default:
            return 0
        }
    }
}

class OLEDView {
    init() {
        
    }

    func run() {
        let driver = ESP32C6U8g2Driver()
        driver.withUnsafeU8g2 { u8g2 in
            u8g2_InitDisplay(u8g2)
            while true {
                u8g2_DrawBox(u8g2, 10, 10, 100, 100)
                u8g2_SetFont(u8g2, Support.default_font)
                u8g2_SendBuffer(u8g2)
                delay_ms(1000)
            }
        }
    }
}