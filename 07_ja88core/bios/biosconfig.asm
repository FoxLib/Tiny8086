; Standard PC-compatible BIOS data area - to copy to 40:0
; https://stanislavs.org/helppc/bios_data_area.html
; ----------------------------------------------------------------------

bios_data:

    com1addr            dw  0
    com2addr            dw  0
    com3addr            dw  0
    com4addr            dw  0
    lpt1addr            dw  0
    lpt2addr            dw  0
    lpt3addr            dw  0
    lpt4addr            dw  0
    equip               dw  0000000000100100b   ; 2=old PC system board RAM < 256K, 5=initial video mode
                        db  0
    memsize             dw  256                 ; Максимум 640, INT 12h
                        db  0
                        db  0
    keyflags1           db  0                   ; 17h
    keyflags2           db  0                   ; 18h
                        db  0
    kbbuf_head          dw  kbbuf-bios_data     ; 1Ah
    kbbuf_tail          dw  kbbuf-bios_data     ; 1Ch
    kbbuf: times 32     db  'X'                 ; 1Eh Клавиатурный буфер
    drivecal            db  0
    diskmotor           db  0
    motorshutoff        db  0x07                ; Декрементируется INT 8h
    disk_laststatus     db  0
    times 7             db  0
    vidmode             db  0x03                ; *Видеорежим
    vid_cols            dw  80                  ; Количество столбцов
    page_size           dw  0x1000
                        dw  0
    curpos_x            db  0                   ; *Положение курсора
    curpos_y            db  0
    times 7             dw  0
    cur_v_end           db  7                   ; *Форма курсора
    cur_v_start         db  6                   ; *OK
    disp_page           db  0                   ; Текущая страница
    crtport             dw  0x3d4               ; Цветной 3D4h
                        db  10
                        db  0
    times 5             db  0
    clk_dtimer          dd  0                   ; Таймер
    clk_rollover        db  0
    ctrl_break          db  0
    soft_rst_flg        dw  0x1234              ; 72h
                        db  0
    num_hd              db  0
                        db  0
                        db  0
                        dd  0
                        dd  0
    kbbuf_start_ptr     dw  0x001e
    kbbuf_end_ptr       dw  0x003e
    vid_rows            db  25                  ; at 40:84 Количество строк
                        db  0
                        db  0
    vidmode_opt         db  0                   ; 0x70
                        db  0                   ; 0x89
                        db  0                   ; 0x51
                        db  0                   ; 0x0c
                        db  0
                        db  0
                        db  0
                        db  0
                        db  0
                        db  0
                        db  0
                        db  0
                        db  0
                        db  0
                        db  0
    kb_mode             db  0
    kb_led              db  0
                        db  0
                        db  0
                        db  0
                        db  0
    boot_device         db  0
    crt_curpos_x        db  0
    crt_curpos_y        db  0
    key_now_down        db  0
    next_key_fn         db  0
    cursor_visible      db  1           ; *Видно ли курсор?
    escape_flag_last    db  0
    next_key_alt        db  0
    escape_flag         db  0
    notranslate_flg     db  0
    this_keystroke      db  0
    this_keystroke_ext  db  0
    timer0_freq         dw  0xFFFF      ; PIT channel 0 (55ms)
    timer2_freq         dw  0           ; PIT channel 2
    cga_vmode           db  0
    vmem_offset         dw  0           ; Video RAM offset

; Keyboard scan code tables

a2shift_tbl db  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db  0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0
            db  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0
            db  1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
            db  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
            db  1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db  0, 0, 0, 1, 1, 1, 1, 0

; ************************* INT 1Eh - diskette parameter table

int1e:

    db 0xdf ; Step rate 2ms, head unload time 240ms
    db 0x02 ; Head load time 4 ms, non-DMA mode 0
    db 0x25 ; Byte delay until motor turned off
    db 0x02 ; 512 bytes per sector

int1e_spt:

    db 18   ; 18 sectors per track (1.44MB)
    db 0x1B ; Gap between sectors for 3.5" floppy
    db 0xFF ; Data length (ignored)
    db 0x54 ; Gap length when formatting
    db 0xF6 ; Format filler byte
    db 0x0F ; Head settle time (1 ms)
    db 0x08 ; Motor start time in 1/8 seconds

; ************************* INT 41h - hard disk parameter table

int41:

int41_max_cyls      dw 1023
int41_max_heads:    db 255

    dw 0
    dw 0
    db 0
    db 11000000b
    db 0
    db 0
    db 0
    dw 0

int41_max_sect:     db 63, 0

; ********************** ROM configuration table ***********************

rom_config:

    dw 16           ; 16 bytes following
    db 0xFE         ; Model
    db 'A'          ; Submodel
    db 'C'          ; BIOS revision
    db 00100000b    ; Feature 1
    db 00000000b    ; Feature 2
    db 00000000b    ; Feature 3
    db 00000000b    ; Feature 4
    db 00000000b    ; Feature 5
    db 0, 0, 0, 0, 0, 0
