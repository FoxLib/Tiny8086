
            org     0

            jmp     near m1
            hlt
            mov     ax, $b800
            mov     ds, ax
            mov     ax, $1721
m1:         mov     cx, 2000
            xor     bx, bx
@@:         mov     [bx], ax
            add     al, 1
            add     bx, 2
            dec     cx
            jne     @b
            je      m1
