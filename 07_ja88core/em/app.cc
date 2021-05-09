// Порты
// 100h RW SPI Data
// 101h  W SPI Command
// 101h  R SPI Status
// =====================================================================

// Реальная запись в память
void writememb(uint32_t address, uint8_t value) {

    RAM[address % RAMTOP] = value;

    // Записываемый байт находится в видеопамяти
    if (address >= 0xB8000 && address < 0xB8FA0) {

        address = (address - 0xB8000) >> 1;
        int col = address % 80;
        int row = address / 80;
        address = 0xB8000 + 160*row + 2*col;
        print_char(col, row, RAM[address], RAM[address + 1]);
    }
}

// Чтение из памяти
uint8_t readmemb(uint32_t address) {
    return RAM[address % RAMTOP];
}

// Ввод данных
uint8_t ioread(uint16_t port) {

    switch (port) {

        case 0x100: return SpiModule.spi_read_data();
        case 0x101: return SpiModule.spi_read_status();

    }

    return io_ports[port];
}

// Вывод
void iowrite(uint16_t port, uint8_t data) {

    switch (port) {

        case 0x100: SpiModule.spi_write_data(data); break;
        case 0x101: SpiModule.spi_write_cmd(data); break;
    }

    io_ports[port] = data;
}

// Сброс процессора
void reset() {

    ms_prevtime = 0;
    initcpu();

    SpiModule.start();
}

// =====================================================================

// Отладка
void regdump() {

/*
    printf("| ax %04X | cx %04X | dx %04X | bx %04X\n", regs16[REG_AX], regs16[REG_CX], regs16[REG_DX], regs16[REG_BX]);
    printf("| sp %04X | bp %04X | si %04X | di %04X\n", regs16[REG_SP], regs16[REG_BP], regs16[REG_SI], regs16[REG_DI]);
    printf("| cs %04X | es %04X | ss %04X | ds %04X\n", regs16[REG_CS], regs16[REG_ES], regs16[REG_SS], regs16[REG_DS]);
    printf("| ip %04X\n", reg_ip);
    printf("| %c%c%c%c%c%c%c%c%c\n",
        flags.o ? 'O' : '-', flags.d ? 'D' : '-', flags.i ? 'I' : '-',
        flags.t ? 'T' : '-', flags.s ? 'S' : '-', flags.z ? 'Z' : '-',
        flags.a ? 'A' : '-', flags.p ? 'P' : '-', flags.c ? 'C' : '-');
*/
}

void memdump(int address) {

    for (int i = 0; i < 4; i++) {

        printf("%05X | ", address + i*16);
        for (int j = 0; j < 16; j++) {
            printf("%02X ", RAM[address + i*16 + j]);
        }
        printf("\n");
    }
}

// Нарисовать точку на экране
void pset(int x, int y, uint32_t color) {

    if (x >= 0 && y >= 0 && x < width && y < height) {
        ( (Uint32*)sdl_screen->pixels )[ x + width*y ] = color;
    }
}

// Печать символа
void print_char(int col, int row, unsigned char pchar, uint8_t attr) {

    // Стандартная DOS-палитра 16 цветов
    uint32_t colors[16] = {
        0x000000, 0x0000cc, 0x00cc00, 0x00cccc,
        0xcc0000, 0xcc00cc, 0xcccc00, 0xcccccc,
        0x888888, 0x0000ff, 0x00ff00, 0x00ffff,
        0xff0000, 0xff00ff, 0xffff00, 0xffffff,
    };

    int x = col*8,
        y = row*16;

    uint8_t fore = attr & 0x0F, // Передний цвет в битах 3:0
            back = attr >> 4;   // Задний цвет 7:4

    // Перебрать 16 строк в 1 символе
    for (int i = 0; i < 16; i++) {

        unsigned char ch = font16[pchar][i];

        // Перебрать 8 бит в 1 байте
        for (int j = 0; j < 8; j++)
            for (int k = 0; k < 4; k++)
                pset(2*(x + j) + (k&1), 2*(y + i) + (k>>1), colors[ ch & (1 << (7 - j)) ? fore : back ]);
    }
}

