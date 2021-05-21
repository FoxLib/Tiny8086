void recalc_cursor() {

    int addr = (cursor_hi*256 + cursor_lo);
    cursor_x = addr % 80;
    cursor_y = addr / 80;
}

// Нарисовать точку на экране
void pset(int x, int y, uint32_t color) {

    if (x >= 0 && y >= 0 && x < width && y < height) {
        ( (Uint32*)sdl_screen->pixels )[ x + width*y ] = color;
    }
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
    if (videomode <= 1) {

        if (address >= 0xB8000 && address < 0xB8FA0) {

            address = (address - 0xB8000) >> 1;
            int col = address % 80;
            int row = address / 80;
            address = 0xB8000 + 160*row + 2*col;
            print_char(col, row, RAM[address], RAM[address + 1]);
        }

    } else if (videomode == 3) {

        if (address >= 0xA0000 && address < 0xAFFFF) {

            address -= 0xA0000;
            int col = address % 320,
                row = address / 320;
            int clr = dac[ RAM[address + 0xA0000] ];

            for (int k = 0; k < 16; k++)
                pset(col*4+(k&3), row*4+(k>>2), clr);
        }
    }
}

// Чтение из памяти
uint8_t readmemb(uint32_t address) {
    return RAM[address % RAMTOP];
}

// Ввод данных
uint8_t ioread(uint16_t port) {

    uint8_t tmp;

    switch (port) {

        // Клавиатура
        case 0x60: return keyb_60h;
        case 0x64: tmp = keyb_64h; keyb_64h &= ~1; return tmp;

        // CGA
        case 0x3D4: return cga_register;
        case 0x3D5:

            switch (cga_register) {

                case 0x0A: return cursor_l;
                case 0x0B: return cursor_h;
                case 0x0E: return cursor_hi;
                case 0x0F: return cursor_lo;
            }
            break;

        // SPI SD
        case 0xFE: return SpiModule.spi_read_status();
        case 0xFF: return SpiModule.spi_read_data();
    }

    return io_ports[port];
}

// Вывод
void iowrite(uint16_t port, uint8_t data) {

    switch (port) {

        // Отсылка EOI
        case 0x20: if (data & 0x20) eoi_master = 0; break;

        case 0x3C8: dac_reg = data; dac_cc = 0; dac_rgb = 0; break;
        case 0x3C9:

            if      (dac_cc == 0) { dac_cc = 1; dac_rgb &= 0x00ffff; dac_rgb |= ((int)(data&0x3f) << 18); }
            else if (dac_cc == 1) { dac_cc = 2; dac_rgb &= 0xff00ff; dac_rgb |= ((int)(data&0x3f) << 10); }
            else if (dac_cc == 2) { dac_cc = 0; dac_rgb &= 0xffff00; dac_rgb |= ((int)(data&0x3f) << 2); dac[dac_reg++] = dac_rgb; }

            break;

        case 0x3D4: cga_register = data; break;
        case 0x3D5:

            switch (cga_register) {

                case 0x0A: cursor_l  = data & 0x3f; break;
                case 0x0B: cursor_h  = data & 0x1f; break;
                case 0x0E: cursor_hi = data & 0x07; recalc_cursor(); break;
                case 0x0F: cursor_lo = data;        recalc_cursor(); break;
            }

            break;

        case 0x3d8:

            videomode = (data & 3);
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

    irr_mask = 0;
    irr_pend = 0;
    irr_vect_master = 0x08;
    irr_vect_slave  = 0x70;
    eoi_master = 0;

    keyb_60h = 0;
    keyb_64h = 0;
    videomode = 0;

    SpiModule.start();
}

// =====================================================================

// Получение XT-кода
// https://ru.wikipedia.org/wiki/%D0%A1%D0%BA%D0%B0%D0%BD-%D0%BA%D0%BE%D0%B4
int get_xt_key(SDL_Event event) {

    /* Получение ссылки на структуру с данными о нажатой клавише */
    SDL_KeyboardEvent * eventkey = & event.key;

    int xt = 0;
    int k  = eventkey->keysym.scancode;

    // printf("%x\n", k);

    switch (k) {

        /* Q */ case 0x18: xt = 0x10; break;
        /* W */ case 0x19: xt = 0x11; break;
        /* E */ case 0x1a: xt = 0x12; break;
        /* R */ case 0x1b: xt = 0x13; break;
        /* T */ case 0x1c: xt = 0x14; break;
        /* Y */ case 0x1d: xt = 0x15; break;
        /* U */ case 0x1e: xt = 0x16; break;
        /* I */ case 0x1f: xt = 0x17; break;
        /* O */ case 0x20: xt = 0x18; break;
        /* P */ case 0x21: xt = 0x19; break;

        /* A */ case 0x26: xt = 0x1E; break;
        /* S */ case 0x27: xt = 0x1F; break;
        /* D */ case 0x28: xt = 0x20; break;
        /* F */ case 0x29: xt = 0x21; break;
        /* G */ case 0x2a: xt = 0x22; break;
        /* H */ case 0x2b: xt = 0x23; break;
        /* J */ case 0x2c: xt = 0x24; break;
        /* K */ case 0x2d: xt = 0x25; break;
        /* L */ case 0x2e: xt = 0x26; break;

        /* Z */ case 0x34: xt = 0x2C; break;
        /* X */ case 0x35: xt = 0x2D; break;
        /* C */ case 0x36: xt = 0x2E; break;
        /* V */ case 0x37: xt = 0x2F; break;
        /* B */ case 0x38: xt = 0x30; break;
        /* N */ case 0x39: xt = 0x31; break;
        /* M */ case 0x3a: xt = 0x32; break;

        /* 0 */ case 0x13: xt = 0x0B; break;
        /* 1 */ case 0x0A: xt = 0x02; break;
        /* 2 */ case 0x0B: xt = 0x03; break;
        /* 3 */ case 0x0C: xt = 0x04; break;
        /* 4 */ case 0x0D: xt = 0x05; break;
        /* 5 */ case 0x0E: xt = 0x06; break;
        /* 6 */ case 0x0F: xt = 0x07; break;
        /* 7 */ case 0x10: xt = 0x08; break;
        /* 8 */ case 0x11: xt = 0x09; break;
        /* 9 */ case 0x12: xt = 0x0A; break;

        /* ~ */ case 0x31: xt = 0x29; break;
        /* - */ case 0x14: xt = 0x0C; break;
        /* = */ case 0x15: xt = 0x0D; break;
        /* \ */ case 0x33: xt = 0x2B; break;
        /* [ */ case 0x22: xt = 0x1A; break;
        /* ] */ case 0x23: xt = 0x1B; break;
        /* ; */ case 0x2f: xt = 0x27; break;
        /* ' */ case 0x30: xt = 0x28; break;
        /* , */ case 0x3b: xt = 0x33; break;
        /* . */ case 0x3c: xt = 0x34; break;
        /* / */ case 0x3d: xt = 0x35; break;

        /* bs */ case 0x16: xt = 0x0E; break; // backspace
        /* sp */ case 0x41: xt = 0x39; break; // space
        /* tb */ case 0x17: xt = 0x0F; break; // tab
        /* ls */ case 0x32: xt = 0x2A; break; // left shift
        /* lc */ case 0x25: xt = 0x1D; break; // left ctrl
        /* la */ case 0x40: xt = 0x38; break; // left alt
        /* en */ case 0x24: xt = 0x1C; break; // enter
        /* es */ case 0x09: xt = 0x01; break; // escape

        // Стрелки
        case 0x6f: xt = 0x48; break; // up
        case 0x72: xt = 0x4D; break; // rt
        case 0x74: xt = 0x50; break; // dn
        case 0x71: xt = 0x4B; break; // lf

        // Функциональные клавиши
        case 0x43:  xt = 0x3B; break; // F1
        case 0x44:  xt = 0x3C; break; // F2
        case 0x45:  xt = 0x3D; break; // F3
        case 0x46:  xt = 0x3E; break; // F4
        case 0x47:  xt = 0x3F; break; // F5
        case 0x48:  xt = 0x40; break; // F6
        case 0x49:  xt = 0x41; break; // F7
        case 0x4A:  xt = 0x42; break; // F8
        case 0x4B:  xt = 0x43; break; // F9
        case 0x4C:  xt = 0x44; break; // F10
        // не работает f11 в sdl у меня
        case 0x60:  xt = 0x58; break; // F12

        default: return -k;
    }

    /* Получить скан-код клавиш */
    return xt;
}

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

    if (videomode <= 1) {
        for (int a = 0xb8000; a <= 0xb9000; a += 2) writememb(a, RAM[a]);
    } else if (videomode == 3) {
        for (int a = 0xa0000; a <= 0xaffff; a++) writememb(a, RAM[a]);
    }
}
