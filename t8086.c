#include <time.h>
#include <sys/timeb.h>
#include <memory.h>
#include <unistd.h>
#include <fcntl.h>
#include "font16.h"
#include "SDL.h"
#include "t8086.h"

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
void wb(int address, unsigned char value) {

    RAM[address] = value;

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
void wr(int address, unsigned int value, unsigned char wsize) {

    if (wsize == 1) {
        wb(address, value);
    } if (wsize == 2) {
        wb(address,   value);
        wb(address+1, value>>8);
    }
}

// Чтение из памяти
unsigned int rd(int address, unsigned char wsize) {

    if (wsize == 1) return RAM[address];
    if (wsize == 2) return RAM[address] + 256*RAM[address+1];

    return 0;
}

// Считывание очередного byte/word из CS:IP
unsigned int fetch(unsigned char wsize) {

    int address = regs16[REG_CS]*16 + regs16[REG_IP];
    regs16[REG_IP] += wsize;
    return rd(address, wsize);
}

// Считывание опкода 000h - 1FFh
unsigned int fetch_opcode() {

    i_size = 0;
    i_rep  = 0;
    segment_over_en = 0;
    segment_id = REG_DS;

    while (i_size < 16) {

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
        return i_w ? regs16[i_rm] : regs[i_rm];
    } else {
        return rd(16*segment_id + i_ea, i_w + 1);
    }
}

// Сохранение данных в R/M
void put_rm(int i_w, unsigned short data) {

    if (i_mod == 3) {
        if (i_w) regs16[i_rm] = data;
        else     regs  [i_rm] = data;
    } else {
        wr(16*segment_id + i_ea, data, i_w + 1);
    }
}

// Выполнение инструкции
void step() {

    opcode_id = fetch_opcode();

    // Если есть байт modrm, запустить его разбор
    if (opcodemap_modrm[opcode_id]) get_modrm();
}

int main(int argc, char* argv[]) {

    char in_start = 1;
    ms_prevtime = 0;

    // Инициализация машины
    regs16  = (unsigned short*) &regs;
    flags.t = 0;

    regs16[REG_AX] = 0x0000;
    regs16[REG_CX] = 0x0000;  // CX:AX размер диска HD
    regs16[REG_DX] = 0x0000;  // Загружаем с FD
    regs16[REG_BX] = 0x0003;
    regs16[REG_SP] = 0x0000;
    regs16[REG_BP] = 0x0000;
    regs16[REG_SI] = 0x0000;
    regs16[REG_DI] = 0x0000;
    regs16[REG_CS] = 0xF000;  // CS = 0xF000
    regs16[REG_IP] = 0x0100;  // IP = 0x0100

    // Загрузка bios в память
    int bios_rom = open("bios.rom", 32898);
    if (bios_rom < 0) { printf("No bios.rom present"); return 1; }
    (void) read(bios_rom, RAM + 0xF0100, 0xFF00);

    // Инициализация окна
    SDL_Init(SDL_INIT_VIDEO);
    sdl_screen = SDL_SetVideoMode(width = 2*640, height = 2*400, 32, SDL_HWSURFACE | SDL_DOUBLEBUF);
    SDL_EnableUNICODE(1);
    SDL_EnableKeyRepeat(500, 30);
    SDL_WM_SetCaption("Эмулятор 8086", 0);

    // Цикл исполнения одной инструкции
    while (in_start) {

        // Проверить наличие нового события
        while (SDL_PollEvent(& sdl_event)) {
            switch (sdl_event.type) {
                case SDL_QUIT: in_start = 0; break;
            }
        }

        // Остановка на перерисовку и ожидание
        ftime(&ms_clock);

        // Вычисление разности времени
        int time_curr = ms_clock.millitm;
        int time_diff = time_curr - ms_prevtime;
        if (time_diff < 0) time_diff += 1000;

        // Если прошло 20 мс, выполнить инструкции, обновить экран
        if (time_diff >= 20) {

            ms_prevtime = time_curr;
            // .. исполнение нескольких инструкции ..
            SDL_Flip(sdl_screen);
        }

        // Задержка исполнения
        SDL_Delay(1);
    }

    SDL_Quit();
    return 0;
}
