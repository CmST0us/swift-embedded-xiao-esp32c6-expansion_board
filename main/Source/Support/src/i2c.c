#include "i2c.h"
#include "driver/i2c.h"
#include "esp_log.h"

static const char *TAG = "I2C";

bool i2c_init(void)
{
    // 先尝试卸载驱动，以防之前有残留
    i2c_driver_delete(I2C_MASTER_NUM);
    
    i2c_config_t conf = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = I2C_SDA_PIN,
        .scl_io_num = I2C_SCL_PIN,
        .sda_pullup_en = GPIO_PULLUP_ENABLE,
        .scl_pullup_en = GPIO_PULLUP_ENABLE,
        .master.clk_speed = 100000,  // 降低到100KHz
    };

    ESP_LOGI(TAG, "正在配置I2C参数...");
    esp_err_t ret = i2c_param_config(I2C_MASTER_NUM, &conf);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "I2C参数配置失败: %d (ESP_ERR_INVALID_ARG = -1)", ret);
        return false;
    }

    ESP_LOGI(TAG, "正在安装I2C驱动...");
    ret = i2c_driver_install(I2C_MASTER_NUM, conf.mode, 0, 0, 0);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "I2C驱动安装失败: %d", ret);
        return false;
    }

    ESP_LOGI(TAG, "I2C初始化成功 - SCL: %d, SDA: %d, 频率: %d Hz", 
             I2C_SCL_PIN, I2C_SDA_PIN, conf.master.clk_speed);
    return true;
}

bool i2c_write_data(uint8_t device_address, uint8_t* data, size_t data_len)
{
    if (data == NULL || data_len == 0) {
        ESP_LOGE(TAG, "I2C写入参数无效");
        return false;
    }

    ESP_LOGI(TAG, "准备写入I2C数据 - 地址: 0x%02x, 长度: %d", device_address, data_len);
    
    i2c_cmd_handle_t cmd = i2c_cmd_link_create();
    if (cmd == NULL) {
        ESP_LOGE(TAG, "I2C命令链接创建失败");
        return false;
    }

    i2c_master_start(cmd);
    i2c_master_write_byte(cmd, (device_address << 1) | I2C_MASTER_WRITE, true);
    i2c_master_write(cmd, data, data_len, true);
    i2c_master_stop(cmd);
    
    ESP_LOGI(TAG, "执行I2C命令...");
    esp_err_t ret = i2c_master_cmd_begin(I2C_MASTER_NUM, cmd, I2C_MASTER_TIMEOUT_MS / portTICK_PERIOD_MS);
    i2c_cmd_link_delete(cmd);
    
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "I2C写入失败: 地址=0x%02x, 长度=%d, 错误码=%d (ESP_ERR_INVALID_ARG = -1)", 
                 device_address, data_len, ret);
        return false;
    }

    ESP_LOGI(TAG, "I2C写入成功: 地址=0x%02x, 长度=%d", device_address, data_len);
    return true;
}

bool i2c_read_data(uint8_t device_address, uint8_t* data, size_t data_len)
{
    i2c_cmd_handle_t cmd = i2c_cmd_link_create();
    i2c_master_start(cmd);
    i2c_master_write_byte(cmd, (device_address << 1) | I2C_MASTER_READ, true);
    if (data_len > 1) {
        i2c_master_read(cmd, data, data_len - 1, I2C_MASTER_ACK);
    }
    i2c_master_read_byte(cmd, data + data_len - 1, I2C_MASTER_NACK);
    i2c_master_stop(cmd);
    
    esp_err_t ret = i2c_master_cmd_begin(I2C_MASTER_NUM, cmd, I2C_MASTER_TIMEOUT_MS / portTICK_PERIOD_MS);
    i2c_cmd_link_delete(cmd);
    
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "I2C读取失败");
        return false;
    }
    return true;
}

bool i2c_write_register(uint8_t device_address, uint8_t reg_address, uint8_t* data, size_t data_len)
{
    i2c_cmd_handle_t cmd = i2c_cmd_link_create();
    i2c_master_start(cmd);
    i2c_master_write_byte(cmd, (device_address << 1) | I2C_MASTER_WRITE, true);
    i2c_master_write_byte(cmd, reg_address, true);
    i2c_master_write(cmd, data, data_len, true);
    i2c_master_stop(cmd);
    
    esp_err_t ret = i2c_master_cmd_begin(I2C_MASTER_NUM, cmd, I2C_MASTER_TIMEOUT_MS / portTICK_PERIOD_MS);
    i2c_cmd_link_delete(cmd);
    
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "I2C寄存器写入失败");
        return false;
    }
    return true;
}

bool i2c_read_register(uint8_t device_address, uint8_t reg_address, uint8_t* data, size_t data_len)
{
    i2c_cmd_handle_t cmd = i2c_cmd_link_create();
    i2c_master_start(cmd);
    i2c_master_write_byte(cmd, (device_address << 1) | I2C_MASTER_WRITE, true);
    i2c_master_write_byte(cmd, reg_address, true);
    i2c_master_start(cmd);
    i2c_master_write_byte(cmd, (device_address << 1) | I2C_MASTER_READ, true);
    if (data_len > 1) {
        i2c_master_read(cmd, data, data_len - 1, I2C_MASTER_ACK);
    }
    i2c_master_read_byte(cmd, data + data_len - 1, I2C_MASTER_NACK);
    i2c_master_stop(cmd);
    
    esp_err_t ret = i2c_master_cmd_begin(I2C_MASTER_NUM, cmd, I2C_MASTER_TIMEOUT_MS / portTICK_PERIOD_MS);
    i2c_cmd_link_delete(cmd);
    
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "I2C寄存器读取失败");
        return false;
    }
    return true;
}
