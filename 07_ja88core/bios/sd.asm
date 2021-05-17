; Отсылка 80 тактов
sd_enable:  call    sd_wait
            mov     al, 0
            call    sd_cmd
            ret

; Ожидание BSY=0
sd_wait:    push    ax
@@:         in      al, $fe
            add     al, al
            jb      @b
            pop     ax
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

; Отсылка команды AH и [sd_arg] к SD
; ----------------------------------------------------------------------

sd_command:

            mov     al, 2
            call    sd_cmd      ; ChipEnable

            ; for 0..65535: if (get() == FF) break;
            mov     cx, 65535
@@:         call    sd_get
            cmp     al, 0xff
            loopnz  @b
            and     cx, cx
            je      .error

            ; Отсылка команды к SD
            mov     al, ah
            or      al, $40
            call    sd_put

            ; Отослать 32-х битную команду
            mov     bx, SD_CMD_ARG+3
            mov     cx, 4
@@:         mov     al, [bx]
            call    sd_put
            dec     bx
            loop    @b

            ; Отправка CRC
            mov     al, 0xff
            cmp     ah, 0
            jne     .c1
            mov     al, 0x95        ; CMD0 with arg 0
            jmp     .c2
.c1:        cmp     ah, 8
            jne     .c2
            mov     al, 0x87        ; CMD8 with arg 0x1AA
.c2:        call    sd_put

            ; Ожидать снятия флага BUSY
            mov     cx, 256
@@:         call    sd_get
            test    al, $80
            loopnz  @b
            and     cx, cx
            je      .error

xor di, di
call print_hex_ax
jmp $


.error:     ; ошибка
            ret
