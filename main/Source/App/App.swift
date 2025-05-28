import Support
import CU8g2

@_silgen_name("cosf") func cosf(_ x: Float) -> Float
@_silgen_name("sinf") func sinf(_ x: Float) -> Float

class App {
    private let driver: ESP32C6U8g2Driver
    private var angleX: Float = 0.0
    private var angleY: Float = 0.0
    
    init() {
        driver = ESP32C6U8g2Driver()
        driver.withUnsafeU8g2 { u8g2 in
            u8g2_InitDisplay(u8g2)
            u8g2_SetPowerSave(u8g2, 0)
            u8g2_ClearBuffer(u8g2)
        }
    }
    
    private func drawCube(angleX: Float, angleY: Float) {
        // 8 vertices of the cube
        let vertices: [(Float, Float, Float)] = [
            (-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
            (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)
        ]
        
        // Rotation matrices
        let cosX = cosf(angleX)
        let sinX = sinf(angleX)
        let cosY = cosf(angleY)
        let sinY = sinf(angleY)
        
        // Projected 2D points
        var points: [(UInt16, UInt16)] = []
        
        // Rotate and project each vertex
        for (x, y, z) in vertices {
            // First rotate around X axis
            let y1 = y * cosX - z * sinX
            let z1 = y * sinX + z * cosX
            
            // Then rotate around Y axis
            let x2 = x * cosY - z1 * sinY
            let z2 = x * sinY + z1 * cosY
            
            // Simple perspective projection
            let scale: Float = 20.0
            let px = UInt16(x2 * scale + 64)
            let py = UInt16(y1 * scale + 32)
            
            points.append((px, py))
        }
        
        // Draw cube edges
        let edges = [
            (0,1), (1,2), (2,3), (3,0),  // Bottom face
            (4,5), (5,6), (6,7), (7,4),  // Top face
            (0,4), (1,5), (2,6), (3,7)   // Connecting lines
        ]
        
        for (start, end) in edges {
            driver.withUnsafeU8g2 { u8g2 in
                u8g2_DrawLine(u8g2, 
                            points[start].0, points[start].1,
                            points[end].0, points[end].1)
            }
        }
    }

    private func drawText() {
        driver.withUnsafeU8g2 { u8g2 in
            u8g2_SetFont(u8g2, Support.default_font_5x7)
            u8g2_SetDrawColor(u8g2, 1)
            u8g2_DrawStr(u8g2, 0, 60, "Swift Embedded @ Eric Wu")
        }
    }

    func run() {
        while true {
            driver.withUnsafeU8g2 { u8g2 in
                u8g2_ClearBuffer(u8g2)
                drawCube(angleX: angleX, angleY: angleY)
                drawText()
                u8g2_SendBuffer(u8g2)
            }
            
            // Update rotation angles
            angleX += 0.05  // X-axis rotation speed
            angleY += 0.08  // Y-axis rotation speed
            
            if angleX > 2 * Float.pi {
                angleX = 0
            }
            if angleY > 2 * Float.pi {
                angleY = 0
            }
            
            delay_ms(16)  // Control rotation speed
        }
    }
}

@_cdecl("app_main")
func main() {
    App().run()
}
