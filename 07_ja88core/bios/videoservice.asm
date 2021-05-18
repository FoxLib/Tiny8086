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
            cmp     ah, 01h
            je      int10_set_cshape
            cmp     ah, 02h
            je      int10_set_cursor
            cmp     ah, 03h
            je      int10_get_cursor
            cmp     ah, 06h  ; Scroll up window
            je      int10_scrollup

            ; 07h Scroll down window
            ; int10_scrolldown

            ; 08h Get character at cursor
            ; int10_charatcur

            ; 09h Write char and attribute
            ; int10_write_char_attrib

            ; 0Eh Write character at cursor position
            ; int10_write_char

            ; 0Fh Get video mode
            ; int10_get_vm

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

; ----------------------------------------------------------------------
; Прокрутка наверх
; AL = число строк для прокрутки (0 = очистка, CH, CL, DH, DL используются)
; BH = атрибут цвета
; CH = номер верхней строки, CL = номер левого столбца
; DH = номер нижней строки, DL = номер правого столбца
; ----------------------------------------------------------------------

int10_scrollup:

            push    ds es
            mov     ds, [cs:SEG_B800h]
            mov     es, [cs:SEG_B800h]

            ; Определение границ
            and     al, al
            jne     @f
            mov     al, 25      ; Если AL=0, то очистка экрана
@@:         cmp     ch, 25
            jnb     .end
            cmp     cl, 80
            jnb     .end
            cmp     dh, 25
            jb      @f
            mov     dh, 24
@@:         cmp     dl, 80
            jb      .scroll
            mov     dl, 79

            ; Прокрутка AL раз
.scroll:    push    ax bx cx dx
            mov     al, 80
            mul     ch
            add     al, cl
            adc     ah, 0
            add     ax, ax
            mov     di, ax       ; DI = 2*(CH*80 + CL)
            lea     si, [di+160] ; SI = DI + 160
            sub     dl, cl
            mov     cl, dl       ; CL = X2-X1+1
            sub     dh, ch       ; DH = Y2-Y1
            mov     ch, 0
            inc     cx
@@:         push    si di cx    ; Прокрутить все окно
            rep     movsw
            pop     cx di si
            add     si, 160
            add     di, 160
            dec     dh
            js      @f          ; Защита от DH=0
            jne     @b
@@:         mov     ah, bh
            mov     al, $20
            lea     di, [si-160]
            rep     stosw       ; Закрасить последнюю строку атрибутом BH
            pop     dx cx bx ax
            dec     al
            jne     .scroll
.end:       pop     es ds
            iret
