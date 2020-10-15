; BIOS грузится по адресу F000:0100

        org     100h

        ; Инициализация
        cli
        cld
        mov     ax, cs
        mov     ds, ax
        mov     ax, $9000
        mov     ss, ax
        mov     ax, $ffff
        mov     es, ax
        mov     si, mem_top
        xor     di, di
        mov     cx, 16
        rep     movsb           ; Копировать строку reboot-кода
        xor     sp, sp          ; SS:SP = $9000:$0000
        hlt

; Эти данные обязательно надо, чтобы были в Memory TOP
mem_top db  0xEA, 0x00, 0x01, 0x00, 0xF0    ; JMP F000:0100
        db  '28/09/20', 0x00, 0xFE, 0x00    ; Параметры

bios_entry:

        jmp     $

