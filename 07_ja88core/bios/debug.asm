print_hex_ax:

            mov     cx, 4
.m1:        rol     ax, 4
            mov     bx, ax
            and     al, $0F
            cmp     al, 10
            jb      @f
            add     al, 7
@@:         add     al, '0'
            mov     ah, $07
            stosw
            mov     ax, bx
            loop    .m1
            ret

cls:        ; ----- pont --------
            mov     ax, 0xb800
            mov     es, ax
            mov     cx, 2000
            xor     di, di
            mov     ax, $0122
@@:         rep     stosw
            ret


outax:      ; Вывод AX на экран
            mov     di, 0xb800
            mov     es, di
            mov     di, 2*(3*80 + 30)
            call    print_hex_ax
            jmp     $
