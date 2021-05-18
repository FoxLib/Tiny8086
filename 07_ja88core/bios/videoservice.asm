SEG_40h     dw      0x0040
SEG_B800h   dw      0xB800

; ----------------------------------------------------------------------
; Видеосервис BIOS
; https://ru.wikipedia.org/wiki/INT_10H
; https://stanislavs.org/helppc/int_10.html
; AH=0 Видеорежим | AL=http://www.columbia.edu/~em36/wpdos/videomodes.txt
; ----------------------------------------------------------------------

int10:      and     ah, ah
            je      int10_set_vm
            cmp     ah, 1
            je      int10_set_cshape
            cmp     ah, 2
            je      int10_set_cursor
            cmp     ah, 3
            je      int10_get_cursor
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

            ; Текущий видеорежим
            mov     es, [cs:SEG_40h]
            mov     [es:vidmode-bios_data], al

            ; Установка и очистка экрана
            mov     es, [cs:SEG_B800h]
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

            push    ax dx es
            mov     es, [cs:SEG_40h]
            mov     word [es:cur_v_end-bios_data], cx
            mov     [es:cursor_visible-bios_data], byte 1
            cmp     ch, cl
            jbe     @f
            mov     [es:cursor_visible-bios_data], byte 0
@@:         mov     dx, 0x3d4
            mov     al, 0x0a
            mov     ah, ch
            out     dx, ax
            inc     al
            mov     ah, cl
            out     dx, ax
            pop     es dx ax
            iret

; ----------------------------------------------------------------------
; Положение курсора
; DH = строка, DL = столбец
; ----------------------------------------------------------------------

int10_set_cursor:

            push    ax bx dx es
            mov     es, [cs:SEG_40h]
            mov     word [es:curpos_x-bios_data], dx
            mov     al, dh
            mov     bl, 80
            mul     bl          ; ax = ch*80
            mov     dh, 0
            add     ax, dx
            mov     bl, al
            mov     al, 0eh
            mov     dx, 3d4h
            out     dx, ax      ; старшие 3 бита
            mov     al, 0fh
            mov     ah, bl
            out     dx, ax      ; младшие 8 бит
            pop     es dx bx ax
            iret

; ----------------------------------------------------------------------
; Положение и размер курсора
; AX = 0
; CH = начальная строка формы курсора,
; CL = конечная строка формы курсора
; DH = строка, DL = столбец
; ----------------------------------------------------------------------

int10_get_cursor:

            push    es
            mov     es, [cs:SEG_40h]
            mov     dx, word [es:curpos_x-bios_data]
            mov     cx, word [es:cur_v_end-bios_data]
            xor     ax, ax
            pop     es
            iret
