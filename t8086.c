#include <time.h>
#include <sys/timeb.h>
#include <memory.h>
#include <unistd.h>
#include <fcntl.h>
#include "font16.h"
#include "SDL.h"
#include "t8086.h"
#include "helpers.c"

// Выполнение инструкции
void step() {

    opcode_id = fetch_opcode();

    // Если есть байт modrm, запустить его разбор
    if (opcodemap_modrm[opcode_id]) get_modrm();

    // Выполнение инструкции
    switch (opcode_id) {

        // XCHG AX, r16
        case 0x90: case 0x91: case 0x92: case 0x93:
        case 0x94: case 0x95: case 0x96: case 0x97: {

            i_reg = opcode_id & 7;
            i_tmp = regs16[REG_AX];
            regs16[REG_AX] = regs16[i_reg];
            regs16[i_reg]  = i_tmp;
            break;
        }

        // CBW, CWD
        case 0x98: regs  [REG_AH] = regs  [REG_AL] &   0x80 ?   0xFF :   0x00; break;
        case 0x99: regs16[REG_DX] = regs16[REG_AX] & 0x8000 ? 0xFFFF : 0x0000; break;

        // FWAIT
        case 0x9B: break;

        // SAHF
        case 0x9E: {

            i_tmp   = regs[REG_AH];
            flags.c = i_tmp & 0x01 ? 1 : 0;
            flags.p = i_tmp & 0x04 ? 1 : 0;
            flags.a = i_tmp & 0x10 ? 1 : 0;
            flags.z = i_tmp & 0x40 ? 1 : 0;
            flags.s = i_tmp & 0x80 ? 1 : 0;
            break;
        }

        // LAHF
        case 0x9F: {

            regs[REG_AH] =
            /* 0 */ (!!flags.c) |
            /* 1 */ 0x02 |
            /* 2 */ (!!flags.p<<2) |
            /* 3 */ 0 |
            /* 4 */ (!!flags.a<<4) |
            /* 5 */ 0 |
            /* 6 */ (!!flags.z<<6) |
            /* 7 */ (!!flags.s<<7);
            break;
        }

        // XLAT
        case 0xD7: {
            regs[REG_AL] = rd(16*regs16[segment_id] + regs16[REG_BX] + regs[REG_AL], 1);
            break;
        }

        // Установка и сброс флагов
        case 0xD6: regs[REG_AL] = flags.c ? 0xFF : 0x00; break; // SALC
        case 0xF4: regs16[REG_IP]--; break;   // HLT
        case 0xF5: flags.c = !flags.c; break; // CMC
        case 0xF8: flags.c = 0; break;        // CLC
        case 0xF9: flags.c = 1; break;        // STC
        case 0xFA: flags.i = 0; break;        // CLI
        case 0xFB: flags.i = 1; break;        // STI
        case 0xFC: flags.d = 0; break;        // CLD
        case 0xFD: flags.d = 1; break;        // STD

        default: ud_opcode(opcode_id);
    }
}

int main(int argc, char* argv[]) {

    char in_start = 1;

    // Инициализация окна
    SDL_Init(SDL_INIT_VIDEO);
    sdl_screen = SDL_SetVideoMode(width = 2*640, height = 2*400, 32, SDL_HWSURFACE | SDL_DOUBLEBUF);
    SDL_EnableUNICODE(1);
    SDL_EnableKeyRepeat(500, 30);
    SDL_WM_SetCaption("Эмулятор 8086", 0);

    reset();

    step();
    regdump();

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
