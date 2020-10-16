
        org     0

        mov     sp, $7c00
        mov     ax, $1720
        xor     bx, bx
        mov     ah, $17
@@:     mov     al, [bx]
        add     al, 1
        mov     [bx], ax
        add     bx, 2
        cmp     bx, 4000
        jne     @b
        hlt
