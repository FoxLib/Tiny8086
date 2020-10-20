
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

// Реальная запись в память
void wb(unsigned int address, unsigned char value) {

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

// Запись значения в память
void wr(unsigned int address, unsigned int value, unsigned char wsize) {

    if (wsize == 1) {
        wb(address, value);
    } if (wsize == 2) {
        wb(address,   value);
        wb(address+1, value>>8);
    }
}

// Чтение из памяти
unsigned int rd(unsigned int address, unsigned char wsize) {

    if (wsize == 1) return RAM[address % RAMTOP];
    if (wsize == 2) return RAM[address % RAMTOP] + 256*RAM[(address+1) % RAMTOP];

    return 0;
}

// Считывание очередного byte/word из CS:IP
unsigned int fetch(unsigned char wsize) {

    unsigned int address = SEGREG(REG_CS, reg_ip);
    reg_ip += wsize;
    return rd(address, wsize);
}

// Считывание опкода 000h - 1FFh
unsigned int fetch_opcode() {

    i_size = 0;
    i_rep  = 0;
    segment_over_en = 0;
    segment_id = REG_DS;
    start_ip = reg_ip;

    while (i_size++ < 16) {

        uint8_t data = fetch(1);

        switch (data) {

            // Получен расширенный опкод
            case 0x0F: return 0x100 + fetch(1);

            // Сегментные префиксы
            case 0x26: segment_over_en = 1; segment_id = REG_ES; break;
            case 0x2E: segment_over_en = 1; segment_id = REG_CS; break;
            case 0x36: segment_over_en = 1; segment_id = REG_SS; break;
            case 0x3E: segment_over_en = 1; segment_id = REG_DS; break;
            case 0x64:
            case 0x65:
            case 0x66:
            case 0x67:
                /* undefined opcode */
                break;
            case 0xF0: break; // lock:
            case 0xF2: i_rep = REPNZ; break;
            case 0xF3: i_rep = REPZ; break;
            default:
                return data;
        }
    }

    /* undefind opcode */
    return 0;
}

// Прочитать эффективный адрес i_ea и параметры modrm
void get_modrm() {

    i_modrm =  fetch(1);
    i_mod   =  i_modrm >> 6;
    i_reg   = (i_modrm >> 3) & 7;
    i_rm    =  i_modrm & 7;
    i_ea    =  0;

    // Расчет индекса
    switch (i_rm) {

        case 0: i_ea = (regs16[REG_BX] + regs16[REG_SI]); break;
        case 1: i_ea = (regs16[REG_BX] + regs16[REG_DI]); break;
        case 2: i_ea = (regs16[REG_BP] + regs16[REG_SI]); break;
        case 3: i_ea = (regs16[REG_BP] + regs16[REG_DI]); break;
        case 4: i_ea =  regs16[REG_SI]; break;
        case 5: i_ea =  regs16[REG_DI]; break;
        case 6: i_ea =  regs16[REG_BP]; break;
        case 7: i_ea =  regs16[REG_BX]; break;
    }

    // В случае если не segment override
    if (!segment_over_en) {

        if ((i_rm == 6 && i_mod) || (i_rm == 2) || (i_rm == 3))
            segment_id = REG_SS;
    }

    // Модифицирующие биты modrm
    switch (i_mod) {

        case 0: if (i_rm == 6) i_ea = fetch(2); break;
        case 1: i_ea += (signed char) fetch(1); break;
        case 2: i_ea += fetch(2); break;
        case 3: i_ea = 0; break;
    }
}

// Получение R/M части; i_w = 1 (word), i_w = 0 (byte)
unsigned int get_rm(int i_w) {

    if (i_mod == 3) {
        return i_w ? regs16[i_rm] : regs[REG8(i_rm)];
    } else {
        return rd(SEGREG(segment_id, i_ea), i_w + 1);
    }
}

// Получение значения регистра из ModRM
uint16_t get_reg(int i_w) {
    return i_w ? regs16[i_reg] : regs[REG8(i_reg)];
}

// Сохранение в регистр
void put_reg(int i_w, uint16_t data) {
    if (i_w) regs16[i_reg] = data;
    else     regs[REG8(i_reg)] = data;
}

// Сохранение данных в R/M
void put_rm(int i_w, unsigned short data) {

    if (i_mod == 3) {
        if (i_w) regs16[i_rm] = data;
        else regs[REG8(i_rm)] = data;
    } else {
        wr(SEGREG(segment_id, i_ea), data, i_w + 1);
    }
}

// Неизвестный опкод
void ud_opcode(int data) {

    printf("UNDEFINED OPCODE: %x\n", data);
    exit(2); // Завершить выполнение машины
}

// Проверка условий
int cond(int cond_id) {

    switch (cond_id & 15) {

        case 0:  return  flags.o; // O
        case 1:  return !flags.o; // NO
        case 2:  return  flags.c; // C
        case 3:  return !flags.c; // NC
        case 4:  return  flags.z; // Z
        case 5:  return !flags.z; // NZ
        case 6:  return  flags.c ||  flags.z; // BE
        case 7:  return !flags.c && !flags.z; // A
        case 8:  return  flags.s; // S
        case 9:  return !flags.s; // NS
        case 10: return  flags.p; // P
        case 11: return !flags.p; // NP
        case 12: return  flags.s != flags.o; // L
        case 13: return  flags.s == flags.o; // NL
        case 14: return (flags.s != flags.o) ||  flags.z; // LE
        case 15: return (flags.s == flags.o) && !flags.z; // G
    }

    return 0;
}

// Вычисление четности
uint8_t parity(uint8_t b) {

    b = (b >> 4) ^ (b & 15);
    b = (b >> 2) ^ (b & 3);
    b = (b >> 1) ^ (b & 1);
    return !b;
}

// Вычисление АЛУ двух чисел 8 (i_w=0) или 16 бит (i_w=1)
// id = 0-ADD, 1-OR, 2-ADC, 3-SBB, 4-AND, 5-SUB, 6-XOR, 7-CMP
uint16_t arithlogic(char id, char i_w, uint16_t op1, uint16_t op2) {

    uint32_t res = 0;

    // Расчет битности
    int bits = i_w ? 0x08000 : 0x080;
    int bitw = i_w ? 0x0FFFF : 0x0FF;
    int bitc = i_w ? 0x10000 : 0x100;

    op1 &= bitw;
    op2 &= bitw;

    // Выбор режима работы
    switch (id) {

        case 0: // ADD
        case 2: // ADC

            res = op1 + op2;

            // Если это ADC, добавляется флаг CF
            if (id == 2) res += !!flags.c;

            flags.c = !!(res & bitc);
            flags.a = !!((op1 ^ op2 ^ res) & 0x10);
            flags.o = !!((op1 ^ op2 ^ bits) & (op1 ^ res) & bits);
            break;

        case 3: // SBB
        case 5: // SUB
        case 7: // CMP

            res = op1 - op2;

            // Если это SBB, вычитается флаг CF
            if (id == 3) res -= !!flags.c;

            flags.c = !!(res & bitc);
            flags.a = !!((op1 ^ op2 ^ res) & 0x10);
            flags.o = !!((op1 ^ op2) & (op1 ^ res) & bits);
            break;

        case 1: // OR
        case 4: // AND
        case 6: // XOR

            if (id == 1) res = op1 | op2;
            if (id == 4) res = op1 & op2;
            if (id == 6) res = op1 ^ op2;

            flags.c = 0;
            flags.a = !!(res & 0x10); // Unknown
            flags.o = 0;
            break;
    }

    // Эти флаги проставляются для всех одинаково
    flags.p = parity(res);
    flags.z = !(res & bitw);
    flags.s = !!(res & bits);

    return res & bitw;
}

// Инструкции сдвига
uint16_t shiftlogic(char id, char i_w, uint16_t op1, uint16_t op2) {

    int cf = 0, i, msb;
    int bits = i_w ? 0x08000 : 0x080;
    int bitw = i_w ? 0x0FFFF : 0x0FF;
    int bitc = i_w ? 0x10000 : 0x100;

    op2 &= (i_w ? 15 : 7);

    switch (id) {

        case 0: { // ROL

            for (i = 0; i < op2; i++) {

                cf  = !!(op1 & bits);
                op1 = ((op1 << 1) | cf) & bitw;
            }

            flags.c = cf;
            flags.o = !!(op1 & bits) ^ cf;
            break;
        }

        case 1: { // ROR

            for (i = 0; i < op2; i++) {

                cf  = op1 & 1;
                op1 = ((op1 >> 1) | (cf ? bits : 0));
            }

            flags.c = cf;
            flags.o = !!((op1 ^ (op1 << 1)) & bits);
            break;
        }

        case 2: { // RCL

            cf = flags.c;
            for (i = 0; i < op2; i++) {

                old_cf = cf;
                cf  = !!(op1 & bits);
                op1 = ((op1 << 1) | old_cf) & bitw;
            }

            flags.c = cf;
            flags.o = cf ^ !!(op1 & bits);
            break;
        }

        case 3: { // RCR

            op1 &= bitw;
            cf   = flags.c;

            for (i = 0; i < op2; i++) {

                old_cf = cf;
                cf  = op1 & 1;
                op1 = (op1 >> 1) | (old_cf ? bits : 0);
            }

            flags.c = cf;
            flags.o = !!((op1 ^ (op1 << 1)) & bits);
            break;
        }

        case 4:
        case 6: { // SHL

            for (i = 0; i < op2; i++) {

                cf  = !!(op1 & bits);
                op1 = (op1 << 1) & bitw;
            }

            if (op2) {

                flags.s = !!(op1 & bits);
                flags.z = !op1;
                flags.p = parity(op1);
                flags.c = cf;
                flags.o = cf ^ flags.s;
            }

            break;
        }

        case 5: { // SHR

            op1 &= bitw;
            if (op2) flags.o = !!(op1 & bits);

            for (i = 0; i < op2; i++) {

                cf  = op1 & 1;
                op1 = (op1 >> 1);
            }

            if (op2) {

                flags.s = !!(op1 & bits);
                flags.z = !op1;
                flags.p = parity(op1);
                flags.c = cf;
            }

            break;
        }

        case 7: { // SAR

            op1 &= bitw;

            for (i = 0; i < op2; i++) {

                msb = op1 & bits;
                cf  = op1 & 1;
                op1 = ((op1 >> 1) | msb);
            }

            flags.o = 0;
            flags.s = !!(op1 & bits);
            flags.z = !op1;
            flags.p = parity(op1);
            flags.c = cf;
            break;
        }
    }

    return op1 & bitw;
}

// Вставить в стек
void push(uint16_t data) {

    regs16[REG_SP] -= 2;
    wr(SEGREG(REG_SS, regs16[REG_SP]), data, 2);
}

// Извлечь из стека
uint16_t pop() {

    uint16_t tw = rd(SEGREG(REG_SS, regs16[REG_SP]), 2);
    regs16[REG_SP] += 2;
    return tw;
}

// Получение флагов
uint16_t get_flags() {

    return
    /* 0 */ (!!flags.c) |
    /* 1 */ 0x02 |
    /* 2 */ (!!flags.p<<2) |
    /* 3 */ 0 |
    /* 4 */ (!!flags.a<<4) |
    /* 5 */ 0 |
    /* 6 */ (!!flags.z<<6) |
    /* 7 */ (!!flags.s<<7) |
    /* 8 */ (!!flags.t<<8) |
    /* 9 */ (!!flags.i<<9) |
    /* 10 */ (!!flags.d<<10) |
    /* 11 */ (!!flags.o<<11) |
    /* 12-15 */ 0xF000;
}

// Сохранить флаги
void set_flags(uint16_t data) {

    // basic
    flags.c = !!(data & 0x01);
    flags.p = !!(data & 0x04);
    flags.a = !!(data & 0x10);
    flags.z = !!(data & 0x40);
    flags.s = !!(data & 0x80);
    // extend
    flags.t = !!(data & 0x100);
    flags.i = !!(data & 0x200);
    flags.d = !!(data & 0x400);
    flags.o = !!(data & 0x800);
}

// Вызов прерывания
void interrupt(uint8_t int_id) {

    push(get_flags());
    push(regs16[REG_CS]);
    push(reg_ip);

    // CS:IP копируется из памяти
    reg_ip = rd(4*int_id, 2);
    regs16[REG_CS] = rd(4*int_id+2, 2);

    flags.i = 0;
    flags.t = 0;
}

// Автоинкремент для строковых инструкции
void incsi(int i_w) { regs16[REG_SI] += (flags.d ? -1 : 1) * (i_w + 1); }
void incdi(int i_w) { regs16[REG_DI] += (flags.d ? -1 : 1) * (i_w + 1); }

void autorep(int i_w, int flag_test) {

    // Есть префикс REP, REPNZ, REPZ
    if (i_rep) {

        // Уменьшаем CX на 1
        regs16[REG_CX]--;

        // Проверка на REPNZ, REPZ
        if (flag_test) {

            // Если REPZ, но не ZERO, переход к следующей инструкции
            if ((i_rep == REPZ)  && !flags.z)
                return;

            // Если REPNZ, но ZERO, переход к следующей инструкции
            if ((i_rep == REPNZ) &&  flags.z)
                return;
        }

        // Повтор инструкции
        if (regs16[REG_CX]) reg_ip = start_ip;
    }
}

// Ввод данных
uint8_t port_in(uint16_t port) {
    return io_ports[port];
}

// Вывод
void port_out(uint16_t port, uint8_t data) {
    io_ports[port] = data;
}

// Вызов INT 8
void call_interrupt8() {

    // Каждые 1..65535 инструкции вызывать проверки
    if (--pit_interval <= 0) {

        ftime(&ms_clock);

        pit_interval  = pit_frequency;
        int time_curr = ms_clock.millitm;
        int time_diff = time_curr - irq8_prevtime;
        if (time_diff < 0) time_diff += 1000;

        // 54.9254 ms = 65536
        int time_pit = pit_frequency / 1191;

        // Вызов прерывания по истечению времени
        if (time_diff >= time_pit) {

            irq8_prevtime = time_curr;
            interrupt(8);
        }
    }
}

// Сброс процессора
void reset() {

    ms_prevtime = 0;

    // Инициализация машины
    regs16  = (unsigned short*) &regs;
    flags.t = 0;
    is_halt = 0;

    // Устройства
    io_hi_lo = 0;
    pit_frequency = 65536;
    pit_interval  = pit_frequency;

    regs16[REG_AX] = 0x4253;
    regs16[REG_CX] = 0x0001;  // CX:AX размер диска HD
    regs16[REG_DX] = 0x0000;  // Загружаем с FD
    regs16[REG_BX] = 0x0002;
    regs16[REG_SP] = 0x0000;
    regs16[REG_BP] = 0x0000;
    regs16[REG_SI] = 0x0000;
    regs16[REG_DI] = 0x0000;
    regs16[REG_SS] = 0x0000;
    regs16[REG_DS] = 0xB800;
    regs16[REG_ES] = 0x0000;
    regs16[REG_CS] = 0xF000;  // CS = 0xF000
    reg_ip         = 0x0100;  // IP = 0x0100
}

// Отладка
void regdump() {

    printf("| ax %04X | cx %04X | dx %04X | bx %04X\n", regs16[REG_AX], regs16[REG_CX], regs16[REG_DX], regs16[REG_BX]);
    printf("| sp %04X | bp %04X | si %04X | di %04X\n", regs16[REG_SP], regs16[REG_BP], regs16[REG_SI], regs16[REG_DI]);
    printf("| cs %04X | es %04X | ss %04X | ds %04X\n", regs16[REG_CS], regs16[REG_ES], regs16[REG_SS], regs16[REG_DS]);
    printf("| ip %04X\n", reg_ip);
    printf("| %c%c%c%c%c%c%c%c%c\n",
        flags.o ? 'O' : '-', flags.d ? 'D' : '-', flags.i ? 'I' : '-',
        flags.t ? 'T' : '-', flags.s ? 'S' : '-', flags.z ? 'Z' : '-',
        flags.a ? 'A' : '-', flags.p ? 'P' : '-', flags.c ? 'C' : '-');
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
