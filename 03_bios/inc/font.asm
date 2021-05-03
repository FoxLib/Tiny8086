
brk
; --------------------
        MOV AX, 0xB800
        MOV ES, AX

        MOV DX, 0x3C4
        MOV AX, 0x0402          ; seq.mapmask = !0, !1, 2, !3
        OUT DX, AX
        MOV AX, 0x0003          ; seq.font A=0 B=0
        OUT DX, AX
        MOV AX, 0x0604          ; seq.memmode = O/E off, chain4 off, ext on
        OUT DX, AX
        MOV DX, 0x3CE
        MOV AX, 0x0005          ; gx.modereg = !256, !shift, !OE, writemode_0
        OUT DX, AX
        MOV AX, 0x0C06          ; gx.miscreg = map_b8000, !HostOE, !graphics
        OUT DX, AX

        ; set font to garbage
        MOV CX, 0x1000
        XOR DI, DI
.loop:  MOV AL, CL
        MOV [ES:DI], CL
        INC DI
        LOOP .loop
; --------------------
;unsigned char seq2, seq4, gc4, gc5, gc6;
;   unsigned font_height, i, j;
;   unsigned char * ptr;

;   outportb(0x3C4, 2);
;   seq2 = inportb(0x3C5);

;   outportb(0x3C4, 4);
;   seq4 = inportb(0x3C5);

;   outportb(0x3C5, seq4 | 0x04);

   ;outportb(0x3CE, 4);
   ;gc4 = inportb(0x3CF);

   ;outportb(0x3CE, 5);
   ;gc5 = inportb(0x3CF);

;   outportb(0x3C4, 2);
;   outportb(0x3C5, seq2);

;   outportb(0x3C4, 4);
;   outportb(0x3C5, seq4);

;   outportb(0x3CE, 4);
;   outportb(0x3CF, gc4);

;   outportb(0x3CE, 5);
;   outportb(0x3CF, gc5);

;   outportb(0x3CE, 6);
;   outportb(0x3CF, gc6);
