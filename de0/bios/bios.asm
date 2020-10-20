
        org     0

        mov     sp, $7c00
        mov     ax, $b800
        mov     ds, ax
        mov     es, ax
        xor     di, di
        mov     cx, 2000
        mov     ax, $0720
        rep     stosw
        xor     bx, bx
b1:     in      al, $64
        test    al, 1
        je      b1
        in      al, $60
        mov     [bx], al
        add     bx, 2
        jmp     b1
