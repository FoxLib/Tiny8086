
; ----------------------------------------------------------------------
; Видеосервис BIOS
; https://stanislavs.org/helppc/int_10.html
; AH=0 Видеорежим | AL=http://www.columbia.edu/~em36/wpdos/videomodes.txt
; ----------------------------------------------------------------------

int10:      and     ah, ah
            je      int10_set_vm
.int10exit: iret

; Видеорежим
; ----------------------------------------------------------------------

int10_set_vm:

            push    es bx
            cmp     al, 3
            jbe     .set_text_mode
            jmp     .exit

.set_text_mode:

            mov     bx, 0xb800
            mov     es, bx
            xor     di, di
            mov     ax, 0x0700
            mov     cx, 80*25
            rep     stosw

.exit:      pop     bx es
            iret
