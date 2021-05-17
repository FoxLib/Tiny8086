
; ----------------------------------------------------------------------
; Видеосервис BIOS
; ----------------------------------------------------------------------

int10:      push    es
            mov     ax, 0xb800
            mov     es, ax

            call    int10_clear_textmode

            pop     es
            iret

; Текущий видеорежим либо CGA, либо TEXTMODE
int10_clear_textmode:

            xor     di, di
            mov     cx, 80*25
            mov     ax, 0x0720
            rep     stosw
            ret
