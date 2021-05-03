
        org     0
        mov     si, ab
        mov     di, ac
        repnz   scasw
@@:     in      al, $64
        and     al, 1
        je      @b
        mov     ax, $A020
        out     $20, ax
        jmp     $

ab:     db      0xAF, 0x20, 0x40, $20
ac:     db      0x83, 0x30, 0x82, $30
