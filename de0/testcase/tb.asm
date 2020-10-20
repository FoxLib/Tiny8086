
        org     0
        mov     cx, 2
        rep     stosw
@@:     in      al, $64
        and     al, 1
        je      @b
        mov     ax, $A020
        out     $20, ax
        jmp     $

