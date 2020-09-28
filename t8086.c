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
