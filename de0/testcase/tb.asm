
        sub     cx, $1234
        push    ax
        pop     cx
        xchg    ax, bx
        jne     a
        mov     ax, $1234
a:      mov     cx, $ffee
