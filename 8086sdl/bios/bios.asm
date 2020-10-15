; BIOS грузится по адресу F000:0100

        org     100h

        ; Инициализация
        cli
        cld
        mov     ax, cs
        mov     ds, ax          ; DS=CS
        xor     ax, ax
        mov     ss, ax          ; SS=$0000
        mov     sp, $7c00       ; SP=$7C00
        dec     ax
        mov     es, ax          ; ES=$FFFF
        xor     di, di          ; DI=$0000
        mov     si, mem_top
        mov     cx, 16
        rep     movsb           ; Копировать строку reboot-кода

        ; Тестовая очистка экрана
        mov     ax, $b800
        mov     es, ax
        xor     di, di
        mov     ax, $1720
        mov     cx, 2000
        rep     stosw

        hlt

; Эти данные обязательно надо, чтобы были в Memory TOP
mem_top db  0xEA, 0x00, 0x01, 0x00, 0xF0    ; JMP F000:0100
        db  '28/09/20', 0x00, 0xFE, 0x00    ; Параметры

bios_entry:

        jmp     $

