; BIOS грузится по адресу F000:0100

        org     100h

        mov     si, _a
        mov     di, _b
        mov     cx, 5

        mov     ax, cs
        mov     ds, ax
        mov     es, ax

        repz cmpsw

        hlt

_a      db "1234"
_b      db "1234"

; Эти данные необходимо обязательно чтобы были в Memory TOP
biosstr db  'Fox8086 BIOS Revision 0.0001', 0, 0
mem_top db  0xEA, 0x00, 0x01, 0x00, 0xF0    ; JMP F000:0100
        db  '28/09/20', 0x00, 0xFE, 0x00    ; Параметры

bios_entry:

        jmp     $

