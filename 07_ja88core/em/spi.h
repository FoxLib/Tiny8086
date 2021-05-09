// Для работы протокола SPI
class APP {
public:

    int spi_data;
    int spi_st;
    int spi_phase;
    int spi_lba;
    int spi_resp;
    int spi_arg;
    int spi_command;
    int spi_crc;
    int spi_status;
    FILE* spi_file;
    unsigned char spi_sector[512];

    unsigned char spi_read_data();
    unsigned char spi_read_status();
    void spi_write_data(unsigned char data);
    void spi_write_cmd(unsigned char data);

    void start() {

        spi_data   = 0; spi_resp     = 0;
        spi_st     = 0; spi_arg      = 0;
        spi_phase  = 0; spi_command  = 0;
        spi_lba    = 0; spi_crc      = 0;
        spi_status = 0;
    }
};

#include "spi.cc"
