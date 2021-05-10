; ----------------------------------------------------------------------
; Обработка прерывания IRQ#1
; ----------------------------------------------------------------------

int9:

        push    es
        push    ax
        push    bx
        push    bp

        in      al, 0x60
        cmp     al, 0x80 ; Key up?
        jae     short no_add_buf
        cmp     al, 0x36 ; Shift?
        je      short no_add_buf
        cmp     al, 0x38 ; Alt?
        je      short no_add_buf
        cmp     al, 0x1d ; Ctrl?
        je      short no_add_buf

        ; Добавление в буфер
        mov     bx, 0x40
        mov     es, bx
        mov     bh, al
        push    bx
        mov     bx, a2scan_tbl
        xlatb
        pop     bx
        mov     bp, [es: kbbuf_tail - bios_data]
        mov     byte [es: bp],   al     ; ASCII code
        mov     byte [es: bp+1], bh     ; Scan code
        add     word [es: kbbuf_tail - bios_data], 2
        call    kb_adjust_buf

no_add_buf:

        mov     al, 0x20
        out     0x20, al        ; EOI

        pop     bp
        pop     bx
        pop     ax
        pop     es
        iret

; Корректировка буфера HEAD/TAIL для клавиатуры
kb_adjust_buf:

        push    ax
        push    bx

        ; Check to see if the head is at the end of the buffer (or beyond). If so, bring it back
        ; to the start

        mov     ax, [es: kbbuf_end_ptr - bios_data]
        cmp     [es: kbbuf_head - bios_data], ax
        jnge    short kb_adjust_tail

        mov     bx, [es: kbbuf_start_ptr - bios_data]
        mov     [es: kbbuf_head - bios_data], bx

kb_adjust_tail:

        ; Проверка что хвост в конце или за буфером, если да, то вернуть назад
        mov     ax, [es: kbbuf_end_ptr - bios_data]
        cmp     [es: kbbuf_tail - bios_data], ax
        jnge    short kb_adjust_done

        mov     bx, [es: kbbuf_start_ptr-bios_data]
        mov     [es: kbbuf_tail-bios_data], bx

kb_adjust_done:

        pop     bx
        pop     ax
        ret
