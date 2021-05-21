microapp:

            mov     ax, $0013
            int     10h

            ; Тестовая палитра
            mov     dx, 3c8h
            xor     ax, ax
            out     dx, al
            inc     dx
@@:         out     dx, al
            out     dx, al
            out     dx, al
            inc     al
            cmp     al, 40h
            jne     @b

            mov     dl, 0
            mov     es, [cs:SEG_A000h]
.3:         xor     di, di
            mov     al, dl
            mov     bx, 200
.2:         mov     cx, 256
.1:         stosb
            inc     al
            loop    .1
            add     di, 320-256
            inc     al
            dec     bx
            jne     .2
            inc     dl
            jmp     .3

            jmp     $

