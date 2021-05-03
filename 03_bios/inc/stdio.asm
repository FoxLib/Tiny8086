; ----------------------------------------------------------------------
; Очистка экрана cls(word attrbyte)
; ----------------------------------------------------------------------
cls:    xor     di, di
        push    bp
        mov     bp, sp
        mov     ax, arg0
        mov     cx, 4000
        rep     stosw
        pop     bp
        ret     2

; ----------------------------------------------------------------------
; Установка положения курсора
; Входное значение arg=(Y*80 + X)
; ----------------------------------------------------------------------

setcursor:

        push    bp
        mov     bp, sp
        push    ax dx
        mov     bx, arg0
        mov     [stdio.cursor], bx
        mov     dx, $3d4
        mov     al, $0f
        out     dx, al      ; outb(0x3D4, 0x0F)
        inc     dx
        mov     al, bl
        out     dx, al      ; outb(0x3D5, pos[7:0])
        dec     dx
        mov     al, $0e
        out     dx, al      ; outb(0x3D4, 0x0E)
        inc     dx
        mov     al, bh
        out     dx, al      ; outb(0x3D5, pos[15:8])
        pop     dx ax
        pop     bp
        ret     2

; ----------------------------------------------------------------------
; Установка курсора (x,y)
; ----------------------------------------------------------------------
locate: push    bp
        mov     bp, sp
        push    ax bx
        mov     ax, arg1        ; Y
        shl     ax, 4
        mov     bx, ax
        shl     ax, 2
        add     bx, ax
        add     bx, arg0        ; X
        invoke  setcursor, bx
        pop     bx ax
        pop     bp
        ret     4

; ----------------------------------------------------------------------
; Печать символа AL в телетайпе
; ----------------------------------------------------------------------

print:  and     al, al
        je      .LR
        push    ax bx cx di
        mov     bx, [stdio.cursor]
        cmp     al, 13              ; Клавиша ENTER
        jne     .L3
        xchg    ax, bx
        mov     bx, 80
        cwd
        div     bx                  ; ax = На какой линии находися
        inc     ax
        cmp     ax, 50
        jb      .L5                 ; Превышение размера экрана
        mov     bx, 8000
        jmp     short .L4
.L5:    invoke  locate,0,ax         ; К следующей строке
        jmp     short .L6

        ; Печать символа
.L3:    add     bx, bx
        mov     [es: bx], al
        add     bx, 2
.L4:    cmp     bx, 8000
        jb      .L2
        ; ---
        xor     di, di              ; Сдвиг экрана наверх
        mov     cx, 3920
.L1:    mov     ax, [es: di + 160]
        stosw
        loop    .L1
        mov     cx, 80              ; Очистить последнюю строку
        mov     al, 0x20
        rep     stosw
        mov     bx, 7840
        ; ---
.L2:    shr     bx, 1
        invoke  setcursor, bx
.L6:    pop     di cx bx ax
.LR:    ret

; ----------------------------------------------------------------------
; Печать форматированной строки
; printf(char* format, ...)
; ----------------------------------------------------------------------
printf: push    bp
        mov     bp, sp
        push    si

        mov     si, arg0
        lea     bx, arg1
.L1:    lodsb                   ; Чтение входного потока символов
        and     al, al
        je      .exit
        cmp     al, '%'
        je      .form
.L2:    call    print
        jmp     short .L1

; Форматированная строка
.form:  lodsb
        cmp     al, 's'
        je      .str            ; Строка
        jmp     .L2             ; Неопознанный символ просто печатать

; Вывести строку %s
.str:   push    si
        mov     si, [ss: bx]
        inc     bx
        inc     bx
@@:     lodsb
        and     al, al
        je      .L3
        call    print
        jmp     @b
.L3:    pop     si
        jmp     short .L1

; Выход из процедуры с очисткой стека
.exit:
        sub     bx, bp
        sub     bx, 4       ; RET, BP
        pop     si bp ax
        add     sp, bx
        push    ax
        ret

; ----------------------------------------------------------------------
stdio:          ; ОБЛАСТЬ ДАННЫХ
; ----------------------------------------------------------------------
.cursor         dw 0
