
; ----------------------------------------------------------------------
; Пропечатать строку из si на экране, ah - цвет, позиция DI

PRINT:  mov     al, [bp]
        inc     bp
        and     al, al
        je      short .exit
        call    PRNCHR
        jmp     PRINT
.exit:  ret

; ----------------------------------------------------------------------
; IN:  AL - символ для печати

PRNCHR: push    ax bx cx si di 

        ; Получение цвета и позиции курсора
        mov     di, [TELETYPE]
        
        ; Специальные символы
        cmp     al, 10 ; CR Caret Return
        je      short .caret
        cmp     al, 13 ; LF Line Feed
        je      short .lf
        
        ; Напечатать новый символ
        mov     ah, [COLOR_PRN]
        mov     [$b000 + di], ax            ; stosw
        inc     di
        inc     di
        mov     [TELETYPE], di
        
        ; Проверить переполнение экрана
        cmp     di, 4000
        je      short .roll    

.cset:  mov     bx, di
        shr     bx, 1
        call    CURSET              ; Установка курсора на новое место
        pop     di si cx bx ax      ; Восстановить старые значения        
        ret

; Возврат каретки. Поскольку деления у меня в процессоре нет, вычисляю 
; остаток через серию минусов
; -------------------

.caret:

        mov     bx, di
@@:     cmp     bx, 160
        jb      short @f
        sub     bx, 160
        jmp     @b
@@:     sub     di, bx
        mov     [TELETYPE], di
        jmp     .cset        

; Line Feed
; -------------------

.lf:    add     di, 160             ; Сдвинуть стркоку вниз
        mov     [TELETYPE], di
        cmp     di, 4000            ; Если она еще в экране
        jb      short .cset         ; То перейти к установке курсора

; Скроллинг вверх
; -------------------

.roll:  mov     si, 0
        mov     cx, 25*80    
@@:     mov     ax, [$b000 + 160 + si]  ; lodsw
        mov     [$b000 + si], ax        ; stosw
        inc     si
        inc     si
        loop    @b   
        
        ; Пропечатать пустую строку
        mov     cx, 80
        mov     ah, [COLOR_PRN]
        mov     al, $00
@@:     mov     [$b000 - 160 + si], ax
        inc     si
        inc     si
        loop    @b
        
        ; Вернуть строку назад
        sub     di, 160                 ; Поднять курсор
        mov     [TELETYPE], di
        jmp     .cset     

; ----------------------------------------------------------------------
; Установка курсора
; bx = X + Y*80

CURSET: mov     dx, $3d4
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
        ret
        
; ----------------------------------------------------------------------
; Очистка экрана
; Параметры: AX - атрибут + символ 

CMD_CLS:

        mov     di, $b000
        mov     cx, 2000
@@:     mov     [di], ax
        inc     di
        inc     di
        loop    @b
        ret
