; Получение ASCII кода нажатого символа
; --------------------------------------------------------
; 1-7  F1-F7
; 8  - Backspace
; 9  - Tab
; 10   F8
; 11   F9
; 12   F10
; 13 - Enter
; 14   F11
; 15   F12
; 27 - ESC
; --------------------------------------------------------

getch:  push    bx
.L1:    in      al, 64h
        and     al, 1
        je      .L1                 ; Ожидание нажатия
        in      al, 60h             ; Прием скан-кода
        cmp     al, $2A
        jne     @f                  ; Клавиша SHIFT нажата
        mov     [.layout_address], word .keyb_up
@@:     cmp     al, $AA
        jne     @f                  ; Клавиша SHIFT отпущена
        mov     [.layout_address], word .keyb_dn
@@:     test    al, $80
        jne     .L1                 ; Отпущенные клавиши не фиксировать
        mov     bx, [.layout_address]
        xlatb
        pop     bx
        ret

.keyb_dn:

    ;    0    1     2    3    4    5    6    7    8    9    A    B    C    D    E    F
    db   0,   27,  '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=',  8,   9    ; 0
    db   'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 13,   0,  'a', 's'   ; 1
    db   'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', $27, '~',  0,  $5C, 'z', 'x', 'c', 'v'   ; 2
    db   'b', 'n', 'm', ',', '.', '/', 0,   '*',  0,  ' ',  0,  1,    2,   3,   4,   5    ; 3
    db   6,   7,   10,  11,  12,  0,   0,   '7', '8', '9', '-', '4', '5', '6', '+', '1'   ; 4
    db   '2', '3', '0', '.', 0,   0,   0,   14,  15,   0,   0,   0,   0,   0,   0,   0    ; 5

.keyb_up:

    ;    0    1     2    3    4    5    6    7    8    9    A    B    C    D    E    F
    db   0,   27,  '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+',  8,   9    ; 0
    db   'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', 13,   0,  'A', 'S'   ; 1
    db   'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~',  0,  '|', 'Z', 'X', 'C', 'V'   ; 2
    db   'B', 'N', 'M', '<', '>', '?', 0,   '*',  0,  ' ',  0,  1,    2,   3,   4,   5    ; 3
    db   6,   7,   10,  11,  12,  0,   0,   '7', '8', '9', '-', '4', '5', '6', '+', '1'   ; 4
    db   '2', '3', '0', '.', 0,   0,   0,   14,  15,   0,   0,   0,   0,   0,   0,   0    ; 5

; Указатель на раскладку клавиатуры
.layout_address dw .keyb_dn




