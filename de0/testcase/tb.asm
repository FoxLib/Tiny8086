
        org     0
        int     5
        hlt
bm:     retf    $0304
@@:     loopnz  @b
        mov     sp, $7c00
        mov     ax, $1721
        mov     bx, $0000
        mov     [bx], ax
xm:     mov     ax, $1234
        ret
        hlt
