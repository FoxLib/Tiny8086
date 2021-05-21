#include <time.h>
#include <sys/timeb.h>
#include <memory.h>
#include <unistd.h>
#include <fcntl.h>
#include "machine.h"

#include "app.cc"

int main(int argc, char* argv[]) {

    char in_start = 1;
    int counter = 0;

    // Инициализация окна
    SDL_Init(SDL_INIT_VIDEO);
    sdl_screen = SDL_SetVideoMode(width = 2*640, height = 2*400, 32, SDL_HWSURFACE | SDL_DOUBLEBUF);
    SDL_EnableUNICODE(1);
    SDL_EnableKeyRepeat(500, 30);
    SDL_WM_SetCaption("Emulator x86", 0);

    reset();

    // Загрузка bios в память
    int bios_rom = open("bios.bin", 32898);
    if (bios_rom < 0) {
        bios_rom = argc > 1 ? open(argv[1], 32898) : -1;
        if (bios_rom < 0) { printf("No bios.bin present"); exit(1); }
    }
    (void) read(bios_rom, RAM + 0xF0000, 0xFF00);

    // Чтение дампа памяти, если есть
    int memory_file = open("memory.bin", 32898);
    if (memory_file) (void) read(memory_file, RAM, 0xFF00);

    // Цикл исполнения одной инструкции
    while (in_start) {

        int xt;

        // Проверить наличие нового события
        while (SDL_PollEvent(& sdl_event)) {

            switch (sdl_event.type) {

                case SDL_QUIT: regdump(); in_start = 0; break;

                // Нажатие на клавишу вызывает запрос прерывания
                case SDL_KEYDOWN:
                case SDL_KEYUP:

                    if ((irr_mask & 2) == 0) {
                        keyb_60h  = get_xt_key(sdl_event) | (sdl_event.type == SDL_KEYUP ? 0x80 : 0);
                        keyb_64h |= 1;
                        irr_pend |= 2;
                    }

                    break;
            }
        }

        // Остановка на перерисовку и ожидание
        ftime(&ms_clock);

        // Вычисление разности времени
        int time_curr = ms_clock.millitm;
        int time_diff = time_curr - ms_prevtime;
        if (time_diff < 0) time_diff += 1000;

        // Если прошло 18 мс, выполнить инструкции, обновить экран
        if (time_diff >= 18) {

            ms_prevtime = time_curr;

            // Системный таймер 18 ms
            if ((irr_mask & 1) == 0) {
                irr_pend |= 1;
            }

            // Прерывание срабатывает только если IF=1 и EOI=0
            if (eoi_master == 0 && (flags & I_FLAG))
            for (int i = 0; i < 8; i++) {
                if (irr_pend & (1 << i)) {
                    irr_pend &= ~(1 << i);
                    eoi_master = 1;
                    interrupt(irr_vect_master + i);
                }
            }

            // 80k x 55 ~ 4.4 MIPS
            if (x86run(80000)) {

                printf("STOP AT %x:%x\n", segs[1], ip);
                regdump();

                in_start = 0; break;
            }

            if (counter++ >= 25) {
                flash_cursor = !flash_cursor;
                screen_redraw();
                counter = 0;
            }

            SDL_Flip(sdl_screen);
        }

        // Задержка исполнения
        SDL_Delay(1);
    }

    SDL_Quit();
    return 0;
}
