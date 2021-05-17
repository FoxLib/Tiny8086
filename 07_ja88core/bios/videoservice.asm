
; ----------------------------------------------------------------------
; Видеосервис BIOS
; https://stanislavs.org/helppc/int_10.html
; AH=0 Видеорежим | AL=http://www.columbia.edu/~em36/wpdos/videomodes.txt
; ----------------------------------------------------------------------

int10:      and     ah, ah
            je      int10_set_vm
            cmp     ah, 1
            je      int10_set_cshape
            cmp     ah, 2
            je      int10_set_cursor
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

; ----------------------------------------------------------------------
; Положение курсора
; DH = строка, DL = столбец
; ----------------------------------------------------------------------

int10_set_cursor:

            push    ax bx dx
            mov     al, dh
            mov     bl, 80
            mul     bl           ; ax = ch*80
            mov     dh, 0
            add     ax, dx
            mov     bl, al
            mov     al, 0eh
            mov     dx, 3d4h
            out     dx, ax      ; старшие 3 бита
            mov     al, 0fh
            mov     ah, bl
            out     dx, ax      ; младшие 8 бит
            pop     dx bx ax
            iret
