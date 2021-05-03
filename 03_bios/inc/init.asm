; Инициализация

INIT:   mov     si, .data
        mov     di, 0
        mov     cx, .ln
@@:     mov     al, [si]
        mov     [di], al
        inc     si
        inc     di
        loop    @b
        ret

.data   dw      0
        db      $07
        dw      keyb_dn
.ln     = $ - .data
        
