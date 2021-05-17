
; ----------------------------------------------------------------------
; Видеосервис BIOS
; https://stanislavs.org/helppc/int_10.html
; AH=0 Видеорежим | AL=http://www.columbia.edu/~em36/wpdos/videomodes.txt
; ----------------------------------------------------------------------

int10:      and     ah, ah
            je      int10_set_vm
            cmp     ah, 1
            je      int10_set_cshape
.int10exit: iret

; ----------------------------------------------------------------------
; Видеорежим: AL=0..3 TEXT
; ----------------------------------------------------------------------

int10_set_vm:

            push    es bx
            cmp     al, 3
            jbe     .set_text_mode
            jmp     .exit

.set_text_mode:

            ; Установка и очистка экрана
            mov     bx, 0xb800
            mov     es, bx
            xor     di, di
            mov     ax, 0x0700
            mov     cx, 80*25
            rep     stosw

.exit:      pop     bx es
            iret

; ----------------------------------------------------------------------
; Вид курсора
; CH-начальная CL-конечная
; ----------------------------------------------------------------------

int10_set_cshape:

            push    ax dx
            mov     dx, 0x3d4
            mov     al, 0x0a
            mov     ah, ch
            out     dx, ax
            inc     al
            mov     ah, cl
            out     dx, ax
            pop     dx ax
            iret
