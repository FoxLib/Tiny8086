
        org     0

        mov     sp, $7c00
        xor     bx, bx
b1:     in      al, $64
        test    al, 1
        je      b1
        in      al, $60
        mov     [bx], al
        add     bx, 2
        jmp     b1
