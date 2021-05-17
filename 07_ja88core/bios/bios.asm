
            ; F000h : 0000
            org     0

bios_entry:

            cli
            cld

            ; interrupt
            mov [0x24], word irq9
            mov [0x26], cs

            ; Обнуляем сегменты ds=ss=0, sp=300h
            ; Находится в Interrupt Vector Table (256b)
            xor     ax, ax
            mov     ds, ax
            mov     ss, ax
            mov     sp, 0x0400
            mov     ax, $b800
            mov     es, ax
            int     9

            ;mov     dx, 0x3d4
            ;mov     ax, 0x040f
            ;out     dx, ax
            ;mov     ax, 0x000e
            ;out     dx, ax

@@:         sti
            jmp @b

            ; -- Чисто сладкая мышь --

            call    cls

            mov     ax, -24
            cwd
            mov     bx, -3
            idiv    bx

            mov     di, 0
            call    print_hex_ax

            ; Ожидание клавиатуры
            mov     di, 0
            mov     ah, $17
@@:         in      al, $64
            test    al, 1
            je      @b
            in      al, $60
            mov     di, 5*2
            call    print_hex_ax
            jmp     @b

            hlt

; --------
irq9:       inc     byte [$1000]
            mov     ah, [$1000]
            in      al, $60
            mov     di, 5*2

            call    print_hex_ax

            mov     [es:di+8], ax

            mov     al, $20
            out     $20, al
            iret

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

            include "biosconfig.asm"
            include "ivt.asm"
            include "keyboard.asm"
            include "debug.asm"
