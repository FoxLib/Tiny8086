void recalc_cursor() {

    int addr = (cursor_hi*256 + cursor_lo);
    cursor_x = addr % 80;
    cursor_y = addr / 80;
}

// Порты
// FFh RW SPI Data
// FFh  W SPI Command
// FFh  R SPI Status
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

        case 0x3D4: return cga_register;
        case 0x3D5:

            switch (cga_register) {

                case 0x0A: return cursor_l;
                case 0x0B: return cursor_h;
            }
            break;

        case 0xFE: return SpiModule.spi_read_status();
        case 0xFF: return SpiModule.spi_read_data();
    }

    return io_ports[port];
}

// Вывод
void iowrite(uint16_t port, uint8_t data) {

    switch (port) {

        case 0x3D4: cga_register = data; break;
        case 0x3D5:

            switch (cga_register) {

                case 0x0A: cursor_l  = data & 0x3f; break;
                case 0x0B: cursor_h  = data & 0x1f; break;
                case 0x0E: cursor_hi = data & 0x07; recalc_cursor(); break;
                case 0x0F: cursor_lo = data;        recalc_cursor(); break;
            }

            break;

        case 0xFE: SpiModule.spi_write_cmd(data); break;
        case 0xFF: SpiModule.spi_write_data(data); break;
    }

    io_ports[port] = data;
}

// Сброс процессора
void reset() {

    ms_prevtime = 0;
    initcpu();

    cursor_x = 0;
    cursor_y = 0;
    cursor_l = 14;
    cursor_h = 15;
    cursor_hi = 0;
    cursor_lo = 0;
    cga_register = 0;

    SpiModule.start();
}

// =====================================================================

// Отладка
void regdump() {

    printf("| ax %04X | cx %04X | dx %04X | bx %04X\n", regs[REG_AX], regs[REG_CX], regs[REG_DX], regs[REG_BX]);
    printf("| sp %04X | bp %04X | si %04X | di %04X\n", regs[REG_SP], regs[REG_BP], regs[REG_SI], regs[REG_DI]);
    printf("| cs %04X | es %04X | ss %04X | ds %04X\n", segs[SEG_CS], segs[SEG_ES], segs[SEG_SS], segs[SEG_DS]);
    printf("| ip %04X\n", ip);
    printf("| %c%c%c%c%c%c%c%c%c\n",
        flags&V_FLAG ? 'O' : '-', flags&D_FLAG ? 'D' : '-', flags&I_FLAG ? 'I' : '-',
        flags&T_FLAG ? 'T' : '-', flags&N_FLAG ? 'S' : '-', flags&Z_FLAG ? 'Z' : '-',
        flags&A_FLAG ? 'A' : '-', flags&P_FLAG ? 'P' : '-', flags&C_FLAG ? 'C' : '-');

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
        for (int j = 0; j < 8; j++) {

            int bitn = !!(ch & (1 << (7 - j)));

            // Мигающий курсор
            if (flash_cursor && i >= cursor_l && i <= cursor_h && cursor_x == col && cursor_y == row)
                bitn ^= 1;

            for (int k = 0; k < 4; k++) {
                pset(2*(x + j) + (k&1), 2*(y + i) + (k>>1), colors[ bitn ? fore : back ]);
            }
        }
    }
}

// Полное обновление экрана
void screen_redraw() {

    for (int a = 0xb8000; a <= 0xb9000; a += 2)
        writememb(a, RAM[a]);
}
