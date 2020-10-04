; BIOS грузится по адресу F000:0100

        org     100h


        mov     sp, $0040
        mov     ax, $b800
        mov     ds, ax
        mov     bx, 0
        mov     ax, $1741
        mov     [bx], ax

        pusha
        popa

        hlt

; Эти данные необходимо обязательно чтобы были в Memory TOP
biosstr db  'Fox8086 BIOS Revision 0.0001', 0, 0
mem_top db  0xEA, 0x00, 0x01, 0x00, 0xF0    ; JMP F000:0100
        db  '28/09/20', 0x00, 0xFE, 0x00    ; Параметры

bios_entry:

        jmp     $

