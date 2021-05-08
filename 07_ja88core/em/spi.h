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
};

#include "spi.cc"
