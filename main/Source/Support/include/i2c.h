#ifndef I2C_H
#define I2C_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

// I2C引脚定义
#define I2C_SCL_PIN     5
#define I2C_SDA_PIN     4

// I2C配置
#define I2C_MASTER_FREQ_HZ    400000  // 400KHz
#define I2C_MASTER_NUM        0       // I2C master number
#define I2C_MASTER_TIMEOUT_MS 1000    // 超时时间

// 函数声明
bool i2c_init(void);
bool i2c_write_data(uint8_t device_address, uint8_t* data, size_t data_len);
bool i2c_read_data(uint8_t device_address, uint8_t* data, size_t data_len);
bool i2c_write_register(uint8_t device_address, uint8_t reg_address, uint8_t* data, size_t data_len);
bool i2c_read_register(uint8_t device_address, uint8_t reg_address, uint8_t* data, size_t data_len);

#endif /* I2C_H */
