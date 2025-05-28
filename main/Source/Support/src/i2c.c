#include "i2c.h"
#include "driver/i2c.h"
#include "esp_log.h"

static const char *TAG = "I2C";

bool i2c_init(void) {
    i2c_config_t conf = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = I2C_SDA_PIN,
        .scl_io_num = I2C_SCL_PIN,
        .sda_pullup_en = GPIO_PULLUP_ENABLE,
        .scl_pullup_en = GPIO_PULLUP_ENABLE,
        .master.clk_speed = I2C_MASTER_FREQ_HZ,  // 100KHz
    };

    ESP_LOGI(TAG, "Configuring I2C parameters...");
    esp_err_t ret = i2c_param_config(I2C_MASTER_NUM, &conf);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "I2C parameter configuration failed: %d (ESP_ERR_INVALID_ARG = -1)", ret);
        return false;
    }

    ESP_LOGI(TAG, "Installing I2C driver...");
    ret = i2c_driver_install(I2C_MASTER_NUM, conf.mode, 0, 0, 0);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "I2C driver installation failed: %d", ret);
        return false;
    }

    ESP_LOGI(TAG, "I2C initialization successful - SCL: %d, SDA: %d, Frequency: %d Hz", 
             I2C_SCL_PIN, I2C_SDA_PIN, conf.master.clk_speed);
    return true;
}

bool i2c_write_data(uint8_t device_address, uint8_t* data, size_t data_len) {
    esp_err_t ret = i2c_master_write_to_device(I2C_MASTER_NUM, device_address, data, data_len, I2C_MASTER_TIMEOUT_MS / portTICK_PERIOD_MS);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "I2C write data failed: %d", ret);
        return false;
    }
    return true;
}
