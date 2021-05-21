
            ; F000h : 0000
            org     0
            include "defines.asm"

bios_entry:

            cli
            cld

            xor     ax, ax
            mov     ds, ax
            mov     ss, ax
            mov     es, ax
            mov     sp, 0x0400

            ; Очистка памяти 1k
            xor     di, di
            mov     cx, 0x400
            rep     stosw

            ; Размещение указателя на параметры жесткого диска
            mov     [4*0x41],   word int41
            mov     [4*0x41+2], cs

            ; Копирование из таблицы
            push    cs
            pop     ds
            mov     si, int_table
            xor     di, di
            mov     cx, 32
@@:         movsw
            mov     ax, cs
            stosw
            loop    @b

            ; Копирование BDA, ds=cs,es=0
            push    cs
            pop     ds
            mov     si, bios_data
            mov     di, 0x400
            mov     cx, 0x100
            rep     movsb

            ; Очистка памяти
            mov     ax, $0003
            int     10h

            ; Переинициализировать сегменты
            xor     ax, ax
            mov     ds, ax
            mov     es, ax
            mov     ss, ax
            mov     sp, 7c00h

            jmp     microapp

            ; Чтение из HD и загрузка в 0:7C00
            mov     dl, 0x80
            sti
            jmp     0 : 0x7c00

            include "sd.asm"
            include "biosconfig.asm"
            include "ivt.asm"
            include "videoservice.asm"
            include "misc.asm"
            include "keyboard.asm"
            include "debug.asm"
            include "microapp.asm"
