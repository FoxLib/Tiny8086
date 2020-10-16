
        org     0

        mov     sp, $7c00
        mov     ax, $F041
        mov     bx, $0000
        mov     [bx], ax
        hlt
