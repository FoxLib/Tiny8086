; BIOS грузится по адресу F000:0100

        org     100h

        cwd

        jmp     bios_entry

; Эти данные необходимо обязательно чтобы были в Memory TOP
biosstr db  '8086tiny BIOS Revision 1.61!', 0, 0
mem_top db  0xEA, 0x00, 0x01, 0x00, 0xF0    ; JMP F000:0100
        db  '28/09/20', 0x00, 0xFE, 0x00    ; Параметры

bios_entry:

        jmp     $

