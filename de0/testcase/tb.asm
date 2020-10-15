
        mov     ax, $82f4
        cwd
        pop     ds
        sub     cx, $1000
        push    ax
        pop     cx
        xchg    ax, bx
        jne     a
        mov     ax, $1234
a:      mov     cx, $ffee
