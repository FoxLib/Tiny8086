; ----------------------------------------------------------------------
; Обработка прерывания IRQ#1
; +---------+----------+------------+-------------+---------------+
; ¦01   Esc ¦12   E    ¦23   H      ¦34   . >     ¦45   NumLock   ¦
; ¦02   1 ! ¦13   R    ¦24   J      ¦35   / ?     ¦46   ScrollLock¦
; ¦03   2 @ ¦14   T    ¦25   K      ¦36 Shft(прав)¦47   Home [7]  ¦
; ¦04   3 # ¦15   Y    ¦26   L      ¦37   * PrtSc ¦48   Up   [8]  ¦
; ¦05   4 $ ¦16   U    ¦27   ; :    ¦38   Alt     ¦49   PgUp [9]  ¦
; ¦06   5 % ¦17   I    ¦28   " '    ¦39   Пробел  ¦4a   K -       ¦
; ¦07   6 ^ ¦18   O    ¦29   ` ~    ¦3a   CapsLock¦4b   <-   [4]  ¦
; ¦08   7 & ¦19   P    ¦2a Shft(лев)¦3b   F1      ¦4c        [5]  ¦
; ¦09   8 * ¦1a   [ {  ¦2b   \ |    ¦3c   F2      ¦4d   ->   [6]  ¦
; ¦0a   9 ( ¦1b   ] }  ¦2c   Z      ¦3d   F3      ¦4e   K +       ¦
; ¦0b   0 ) ¦1c   Enter¦2d   X      ¦3e   F4      ¦4f   End  [1]  ¦
; ¦0c   - _ ¦1d   Ctrl ¦2e   C      ¦3f   F5      ¦50   Dn   [2]  ¦
; ¦0d   + = ¦1e   A    ¦2f   V      ¦40   F6      ¦51   PgDn [3]  ¦
; ¦0e   Bksp¦1f   S    ¦30   B      ¦41   F7      ¦52   Ins  [0]  ¦
; ¦0f   Tab ¦20   D    ¦31   N      ¦42   F8      ¦53   Del  [.]  ¦
; ¦10   Q   ¦21   F    ¦32   M      ¦43   F9      ¦               ¦
; ¦11   W   ¦22   G    ¦33   , <    ¦44   F10     ¦               ¦
; +---------+----------+------------+-------------+---------------+


; ----------------------------------------------------------------------
; Сервис клавиатуры
; https://www.frolov-lib.ru/books/bsp/v02/ch2_4.htm
; ----------------------------------------------------------------------

int16:      cmp     ah, 0x00
            je      int16_kb_wait
            cmp     ah, 0x01
            je      int16_kb_checkkey
            cmp     ah, 0x02
            je      int16_kb_shiftflags
            ;cmp     ah, 0x12
            ;je      int16_kb_extshiftflags
            iret

; ----------------------------------------------------------------------
; Обработка прерывания
; ----------------------------------------------------------------------

int9:       push    ax bx cx dx ds
            in      al, $60

            ; BDA
            mov     ds, [cs:SEG_40h]
            mov     bx, keyflags1-bios_data

            ; SHIFT LEFT
            cmp     al, $2A+$80
            jne     @f
            and     [bx], byte 11111101b
            jmp     .skip_key
@@:         cmp     al, $2A
            jne     @f
            or      [bx], byte 00000010b
            jmp     .skip_key
            ; SHIFT RIGHT
@@:         cmp     al, $36+$80
            jne     @f
            and     [bx], byte 11111110b
            jmp     .skip_key
@@:         cmp     al, $36
            jne     @f
            or      [bx], byte 00000001b
            jmp     .skip_key
            ; CTRL
@@:         cmp     al, $1D+$80
            jne     @f
            and     [bx], byte 11111011b
            jmp     .skip_key
@@:         cmp     al, $1D
            jne     @f
            or      [bx], byte 00000100b
            jmp     .skip_key
@@:         ; ALT
            cmp     al, $38+$80
            jne     @f
            and     [bx], byte 11110111b
            jmp     .skip_key
@@:         cmp     al, $38
            jne     @f
            or      [bx], byte 00001000b
            jmp     .skip_key

            ; Не пропускать отжатые клавиши в клавиатурный буфер
@@:         test    al, $80
            jne     .skip_key

            ; Трансляция скан-кода
            test    [bx], byte 2        ; Проверка на то, что SHIFT нажат
            mov     bx, a1scan_tbl
            je      @f                  ; Если 0, то shift не нажат
            mov     bx, a2scan_tbl

@@:         ; Трансляция скан-кода в ASCII
            push    ds
            push    cs
            pop     ds
            mov     ah, al
            xlatb
            pop     ds

            ; Добавить в буфер новое значение
            cmp     al, 0x20
            jb      @f
            mov     ah, 0
@@:         mov     bx, [kbbuf_head-bios_data]

            ; Добавление нового символа и сдвиг курсора вперед
            ; с учетом цикличности буфера
            mov     [bx], ax
            add     bx, 2
            cmp     bx, kbbuf-bios_data+32
            jb      @f
            mov     bx, kbbuf-bios_data
@@:         mov     [kbbuf_head-bios_data], bx

            ; Выход из IRQ-прерывания
.skip_key:  mov     al, $20
            out     $20, al
            pop     ds dx cx bx ax
            iret

; ----------------------------------------------------------------------
; AH = 0
; AL = ASCII-код символа или 0, если AH содержит расширенный ASCII-код символа
; AH = скан-код или расширенный ASCII-код символа, если AL=0.
; ----------------------------------------------------------------------

int16_kb_wait:

            push    ds dx cx bx
            mov     ds, [cs:SEG_40h]
@@:         cli
            mov     bx, [kbbuf_tail-bios_data]
            mov     dx, [kbbuf_head-bios_data]
            sti
            cmp     bx, dx
            je      @b
            cli
            call    int16_kb_nextkey
            pop     bx cx dx ds
            iret

; ----------------------------------------------------------------------
; AH = 1
; На выходе: ZF = 0, если в буфере имеется код нажатой на клавиатуре клавиши;
;            ZF = 1, если буфер клавиатуры пуст
; ----------------------------------------------------------------------

INT16_FLAGS equ 14

int16_kb_checkkey:

            push    ds dx cx bx bp
            mov     bp, sp
            mov     al, [bp+INT16_FLAGS]
            or      al, 01000000b       ; ZF=1
            mov     [bp+INT16_FLAGS], al
            mov     ds, [cs:SEG_40h]
            xor     ax, ax
            mov     bx, [kbbuf_tail-bios_data]
            mov     dx, [kbbuf_head-bios_data]
            cmp     dx, bx
            je      .end                ; ZF=1, буфер пуст
            mov     al, [bp+INT16_FLAGS]
            and     al, 10111111b       ; ZF=0
            mov     [bp+INT16_FLAGS], al
.end:       pop     bp bx cx dx ds
            iret

; Получение следующей клавиши
int16_kb_nextkey:

            mov     bx, [kbbuf_tail-bios_data]
            mov     ax, [bx]
            add     bx, 2
            cmp     bx, kbbuf-bios_data+32
            jb      @f
            mov     bx, kbbuf-bios_data
@@:         mov     [kbbuf_tail-bios_data], bx
            ret

; ----------------------------------------------------------------------
; На входе:       AH = 02h
; На выходе:      AL = Байт состояния переключающих клавиш
; 0 Нажата правая клавиша Shift.
; 1 Нажата левая клавиша Shift.
; 2 Нажата комбинация клавиш Ctrl-Shift с любой стороны.
; 3 Нажата комбинация клавиш Alt-Shift с любой стороны.
; 4 Состояние клавиши ScrollLock.
; 5 Состояние клавиши NumLock.
; 6 Состояние клавиши CapsLock.
; 7 Состояние клавиши Insert.
; ----------------------------------------------------------------------

int16_kb_shiftflags:

            push    ds
            mov     ds, [cs:SEG_40h]
            mov     al, [keyflags1-bios_data]
            and     al, 15
            pop     ds
            iret

; ----------------------------------------------------------------------
; Преобразование скан-кода
; ----------------------------------------------------------------------

; Основная таблица
;                  0     1     2     3     4     5     6     7     8     9     A     B     C     D     E     F
a1scan_tbl: db  0x00, 0x1B,  '1',  '2',  '3',  '4',  '5',  '6',  '7',  '8',  '9',  '0',  '-',  '=', 0x08, 0x09 ; 0
            db   'q',  'w',  'e',  'r',  't',  'y',  'u',  'i',  'o',  'p',  '[',  ']', 0x0D, 0x00,  'a',  's' ; 1
            db   'd',  'f',  'g',  'h',  'j',  'k',  'l',  ';', 0x27,  '`', 0x00, 0x5C,  'z',  'x',  'c',  'v' ; 2
            db   'b',  'n',  'm',  ',',  '.',  '/', 0x00, 0x00, 0x00,  ' ', 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 3
            db  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 4
            db  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 5

; Таблица с SHIFT
a2scan_tbl: db  0x00, 0x1B,  '!',  '@',  '#',  '$',  '%',  '^',  '&',  '*',  '(',  ')',  '_',  '+', 0x08, 0x09 ; 0
            db   'Q',  'W',  'E',  'R',  'T',  'Y',  'U',  'I',  'O',  'P',  '{',  '}', 0x0D, 0x00,  'A',  'S' ; 1
            db   'D',  'F',  'G',  'H',  'J',  'K',  'L',  ':',  '"',  '~', 0x00,  '|',  'Z',  'X',  'C',  'V' ; 2
            db   'B',  'N',  'M',  '<',  '>',  '?', 0x00, 0x00, 0x00,  ' ', 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 3
            db  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 4
            db  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 5
