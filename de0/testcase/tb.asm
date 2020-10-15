
        push    ax
        pop     ds
        sub     cx, $1000
        push    ax
        pop     cx
        xchg    ax, bx
        jne     a
        mov     ax, $1234
a:      mov     cx, $ffee
