SEG_40h     dw      0x0040
SEG_B800h   dw      0xB800
SEG_A000h   dw      0xA000

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
            cmp     ah, 06h
            je      int10_scrollup

            ; 07h Scroll down window
            ; int10_scrolldown

            ; 08h Get character at cursor
            ; int10_charatcur

            ; 09h Write char and attribute
            ; int10_write_char_attrib

            cmp     ah, 0Eh
            je      int10_write_char

mov al, ah
jmp $

            cmp     ah, 0Fh
            je      int10_get_vm

.int10exit: iret

; ----------------------------------------------------------------------
; Видеорежим: AL=0..3 TEXT; 13 VGA 320x200
; ----------------------------------------------------------------------

int10_set_vm:

            push    es bx cx dx di

            mov     es, [cs:SEG_40h]
            mov     [es:vidmode-bios_data], al
            mov     dx, 3d8h
            xor     di, di

            cmp     al, 3
            jbe     .set_text_mode
            cmp     al, 13h
            je      .set_320mode
            jmp     .exit

.set_text_mode:

            ; Переход в текстовый видеорежим
            mov     al, 1
            out     dx, al

            ; Установка и очистка экрана
            mov     es, [cs:SEG_B800h]
            mov     ax, 0x0700
            mov     cx, 80*25
            rep     stosw
            jmp     .exit

.set_320mode:

            ; Переход в графический видеорежим
            mov     al, 3
            out     dx, al
            mov     es, [cs:SEG_A000h]
            xor     ax, ax
            mov     cx, 320*100
            rep     stosw

.exit:      pop     di dx cx bx es
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

            call    int10_scrollup_routine
            iret

; Общий скроллинг для разных целей
int10_scrollup_routine:

            push    ds es ax bx cx dx
            call    int10_scrollbound
.repeat:    push    ax bx cx dx     ; Прокрутка AL раз
            mov     al, 80
            mul     ch
            add     al, cl
            adc     ah, 0
            add     ax, ax
            mov     di, ax          ; DI = 2*(CH*80 + CL)
            lea     si, [di+160]    ; SI = DI + 160
            sub     dl, cl
            mov     cl, dl          ; CL = X2-X1+1
            sub     dh, ch          ; DH = Y2-Y1
            mov     ch, 0
            inc     cx
@@:         push    si di cx        ; Прокрутить все окно
            rep     movsw
            pop     cx di si
            add     si, 160
            add     di, 160
            dec     dh
            js      @f              ; Защита от DH=0
            jne     @b
@@:         mov     ah, bh
            mov     al, $20
            lea     di, [si-160]
            rep     stosw           ; Закрасить последнюю строку атрибутом BH
            pop     dx cx bx ax
            dec     al
            jne     .repeat
.end:       pop     dx cx bx ax es ds
            ret

; Определение границ области CX:DX
int10_scrollbound:

            mov     ds, [cs:SEG_B800h]
            mov     es, [cs:SEG_B800h]
            and     al, al          ; Определение границ
            jne     @f
            mov     al, 25          ; Если AL=0, то очистка экрана
@@:         cmp     ch, 25
            jb      @f
            mov     ch, 24
@@:         cmp     cl, 80
            jb      @f
            mov     cl, 79
@@:         cmp     dh, 25
            jb      @f
            mov     dh, 24
@@:         cmp     dl, 80
            jb      .end
            mov     dl, 79
.end:       ret

; ----------------------------------------------------------------------
; Получение видеорежима 0Fh
; ----------------------------------------------------------------------

int10_get_vm:

            push    ds
            mov     ds, [cs:SEG_40h]
            mov     ah, 80
            mov     al, [es:vidmode-bios_data]
            mov     bh, 0
            pop     es
            iret

; ----------------------------------------------------------------------
; Печать символа в положении текущего курсора в строчном режиме
; AL-символ BL-цвет (только для графики)
; BEL (07h), BS (08h), LF (0Ah), and CR (0Dh)
; ----------------------------------------------------------------------

int10_write_char:

            push    ds es ax bx cx dx si di

            ; Используемые адреса ds/es
            push    ax
            mov     ds, [cs:SEG_40h]
            mov     es, [cs:SEG_B800h]

            ; Текущее положение курсора
            mov     bx, word [curpos_x-bios_data]
            mov     al, bh
            mov     ah, 80
            mul     ah
            mov     bh, 0
            add     ax, bx
            add     ax, ax      ; ax=2*(80*bh+bl)
            mov     di, ax
            pop     ax


            ; Управляющие символы
            mov     bx, word [curpos_x-bios_data]
            cmp     al, 0x0A
            je      .LF         ; Y++
            cmp     al, 0x0D
            je      .CR         ; X=0
            cmp     al, 0x07
            je      .next1
            cmp     al, 0x08
            jne     .psym
            and     bl, bl
            je      .next1
            dec     bl
            jmp     .next1

.psym:      ; Печать символа
            stosb

            ; Следующий символ
            inc     bl
            cmp     bl, 80
            jb      .next1
            inc     bh          ; Y++
            jmp     .CR
.LF:        inc     bh          ; Y++
            jmp     .LFO
.CR:        mov     bl, 0
.LFO:       cmp     bh, 25
            jb      .next1
            mov     bh, 24

            ; Скроллинг экрана наверх
            push    bx
            mov     ax, 0601h
            mov     bh, 07h
            mov     cx, 0000h
            mov     dx, 184Fh
            int     10h
            pop     bx

            ; Установка нового положения курсора
.next1:     mov     word [curpos_x-bios_data], bx
            mov     dx, bx
            mov     ah, 2
            int     10h

            pop     di si dx cx bx ax es ds
            iret
