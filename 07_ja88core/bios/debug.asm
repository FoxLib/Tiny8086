print_hex_ax:

            mov     bx, $b800
            mov     es, bx
            mov     cx, 4
.m1:        rol     ax, 4
            mov     bx, ax
            and     al, $0F
            cmp     al, 10
            jb      @f
            add     al, 7
@@:         add     al, '0'
            mov     [es:di], al
            inc     di
            inc     di
            mov     ax, bx
            loop    .m1
            ret

cls:        ; ----- pont --------
            mov     ax, 0xb800
            mov     es, ax
            mov     cx, 2000
            xor     di, di
@@:         mov     [es:di], word $1720
            inc     di
            inc     di
            loop    @b
            ret
