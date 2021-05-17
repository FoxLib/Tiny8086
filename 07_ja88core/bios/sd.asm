; Отсылка 80 тактов
sd_enable:  call    sd_wait
            mov     al, 0
            call    sd_cmd
            ret

; Ожидание BSY=0
sd_wait:    mov     bp, ax
@@:         in      al, $fe
            add     al, al
            jb      @b
            mov     ax, bp
            ret

; Отсылка команды AL к SD
sd_cmd:     and     al, $03
            out     $fe, al
            or      al, $80
            out     $fe, al
            call    sd_wait
            and     al, $03
            out     $fe, al
            ret

; Запись в SD
sd_put:     call    sd_wait
            out     $ff, al
            mov     al, 1
            call    sd_cmd
            ret

; Чтение из SD
sd_get:     mov     al, 0xff
            call    sd_put
            call    sd_wait
            in      al, $ff     ; Прием результата
            ret

; Инициализация карты
; ----------------------------------------------------------------------

sd_init:    mov     al, 2
            call    sd_cmd      ; ChipEnable

            ; for 0..65535: if (get() == FF) break;
            mov     cx, 65535
@@:         call    sd_get
            cmp     al, 0xff
            loopnz  @b
            and     cx, cx
            je      .error

mov ax, cx
xor di, di
call print_hex_ax
jmp $


.error:     ; ошибка
            ret
