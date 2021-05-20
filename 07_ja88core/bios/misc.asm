; ----------------------------------------------------------------------
int8:
            push    ax ds
            mov     ds, [cs:SEG_40h]

            ; Инкрементировать таймер
            mov     ax, word [clk_dtimer-bios_data]
            add     ax, 1
            mov     word [clk_dtimer-bios_data], ax
            mov     ax, word [clk_dtimer-bios_data+2]
            adc     ax, 0
            mov     word [clk_dtimer-bios_data+2], ax

            ; Завершить прерывание
            mov     al, 0x20
            out     $20, al
            pop     ds ax
            iret

; ----------------------------------------------------------------------
int1a:      cmp     ah, 0
            je      int1a_getsystime    ; Получение тиков с момента сброса
            cmp     ah, 2
            je      int1a_gettime       ; Получение RTC time
            cmp     ah, 4
            je      int1a_getdate       ; Получение RTC date
            cmp     ah, 0x0F
            je      int1a_init          ; Инициализация RTC
            iret

; Получение количества тиков
int1a_getsystime:

            push    ds
            mov     ds, [cs:SEG_40h]
            mov     cx, word [clk_dtimer-bios_data+2]
            mov     dx, word [clk_dtimer-bios_data]
            pop     ds
            iret

int1a_gettime:
int1a_getdate:
int1a_init:
            iret
