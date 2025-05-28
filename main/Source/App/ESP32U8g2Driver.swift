import U8g2Kit
import CU8g2
import Support

class ESP32C6U8g2Driver: Driver {

    private let OLED_ADDRESS: UInt8 = 0x3C

    private var buffer: [UInt8] = Array(repeating: 0, count: 128)
    private var bufferIndex: Int = 0
    
    init() {
        super.init(u8g2_Setup_ssd1306_i2c_128x64_noname_f, &U8g2Kit.u8g2_cb_r0)
        // Mask use this, otherwise i2c_driver_install will not found
        let installHandler = i2c_driver_install
    }

    override func onByte(msg: UInt8, arg_int: UInt8, arg_ptr: UnsafeMutableRawPointer?) -> UInt8 {
        switch Int32(msg) {
        case U8X8_MSG_BYTE_INIT:
            i2c_init()
            return 1
            
        case U8X8_MSG_BYTE_START_TRANSFER:
            bufferIndex = 0
            return 1
            
        case U8X8_MSG_BYTE_SEND:
            if let ptr = arg_ptr {
                let data = UnsafeMutableBufferPointer<UInt8>(start: ptr.assumingMemoryBound(to: UInt8.self), count: Int(arg_int))
                for i in 0..<Int(arg_int) {
                    if bufferIndex < buffer.count {
                        buffer[bufferIndex] = data[i]
                        bufferIndex += 1
                    }
                }
            }
            return 1
            
        case U8X8_MSG_BYTE_END_TRANSFER:
            if bufferIndex > 0 {
                let result = i2c_write_data(OLED_ADDRESS, &buffer, bufferIndex)
                return result ? 1 : 0
            }
            return 1
            
        default:
            return 1
        }
    }
}