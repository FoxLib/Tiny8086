
            org     100h

            mov     ax, $0003
            int     10h
            mov     bx, $b800
            mov     es, bx
            xor     di, di
            mov     cx, 2000
            mov     ax, $1700
@@:         stosw
            inc     ax
            loop    @b

            mov     ah, 6
            mov     al, 0
            mov     bh, 0x07 ; Атрибут
            mov     ch, 1  ; Верх
            mov     cl, 1  ; Лево
            mov     dh, 24 ; Низ
            mov     dl, 79 ; Право
            int     10h
            int3
