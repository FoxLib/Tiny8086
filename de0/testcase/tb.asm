
        org     0

        mov     sp, $7c00
        mov     ax, $1721
        mov     bx, $0000
        mov     [bx], ax
        hlt
