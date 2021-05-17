
            ; F000h : 0000
            org     0

bios_entry:

            cli
            cld
            xor     ax, ax
            mov     ds, ax
            mov     ss, ax
            mov     ax, $b800
            mov     es, ax
            mov     sp, 0x0400

            call    sd_enable
            call    sd_init



            ;mov     ax, $1234
            ;xor     di, di
            ;call    print_hex_ax

@@:
            jmp @b


            ; Установка IVT (2kb)
            xor     di, di
            mov     cx, 1024
            rep     stosw

            ; Копирование из таблицы
            xor     di, di
            mov     si, int_table
            mov     cx, 32
@@:         movsw
            mov     ax, cs
            movsw
            loop    @b

            ; Размещение указателя на параметры жесткого диска
            mov     [4*0x41],   word int41
            mov     [4*0x41+2], cs

            ; Копирование BDA, ds=cs
            push    cs
            pop     ds
            mov     si, bios_data
            mov     di, 0x400
            mov     cx, 0x100
            rep     movsb

            ; Очистка памяти
            mov     ax, 0xb800
            mov     es, ax
            xor     di, di
            mov     cx, 80*25
            mov     ax, 0x0720
            rep     stosw

            ; Чтение из HD и загрузка в 0:7C00
hlt
            xor     ax, ax
            mov     es, ax
            mov     ax, 0x0201
            mov     dh, 0
            mov     dl, 0x80
            mov     cx, 1
            mov     bx, 0x7c00
            int     13h

            ; Jump to boot sector

            jmp     $

            include "sd.asm"
            include "biosconfig.asm"
            include "ivt.asm"
            include "keyboard.asm"
            include "debug.asm"
