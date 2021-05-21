module core88
(
    input   wire        clock,
    input   wire        resetn,
    input   wire        locked,

    // Данные
    output  wire [19:0] address,
    input   wire [ 7:0] bus,
    output  reg  [ 7:0] data,
    output  reg         wreq,

    // Порты
    output  reg         port_clk,
    output  reg  [15:0] port,
    input   wire [ 7:0] port_i,
    output  reg  [ 7:0] port_o,
    output  reg         port_w,

    // Прерывания
    input   wire        intr,       // Запрос прерывания
    input   wire [ 7:0] irq,        // Номер прерывания
    output  reg         intr_latch, // ACCEPT прерывания

    // Отладочные LED
    output  wire [23:0] debug
);

`include "decl.v"

wire __m0 = (mode == PREPARE);

// Выбор источника памяти
assign address = sel ? {seg_ea, 4'h0} + ea : {seg_cs, 4'h0} + ip;

assign debug = {eax[7:0], ip[15:0]};

// =====================================================================
// Основная работа процессорного микрокода, так сказать
// =====================================================================

// Считать такты процессора
always @(posedge clock) rdtsc <= rdtsc + 1;

always @(posedge clock)
// Сброс
if (resetn == 0) begin seg_cs <= 16'hF000; ip <= 0; mode <= PREPARE; end
// Исполнение
else if (locked) case (mode)

    // Считывание опкода, сброс, прерывания
    PREPARE: begin

        opcode  <= bus;
        idir    <= 0;
        isize   <= 0;
        modrm   <= 0;
        opsize  <= 0;
        adsize  <= 0;
        sel_seg <= 0;
        sel_rep <= 0;
        stack32 <= 0;
        skip_op <= 0;
        seg_ea  <= seg_ds;
        tstate  <= 0;
        estate  <= 0;
        ipstart <= ip;

        // Есть наличие IRQ из контроллера прерываний
        if (flags[IF] & (intr ^ intr_latch)) begin

            is_intr <= 1;
            mode    <= INTERRUPT;
            wb      <= irq;
            intr_latch <= intr;

            // Разблокировка HLT
            if (bus == 8'hF4) ip <= ip + 1;

        end
        else begin

            is_intr <= 0;
            ip      <= ip + 1;
            mode    <= MAIN;

        end

    end

    // Исполнение инструкции
    MAIN: casex (opcode)

        // ПРЕФИКСЫ:
        8'h26: begin opcode <= bus; ip <= ip + 1; sel_seg <= 1; seg_ea <= seg_es; end
        8'h2E: begin opcode <= bus; ip <= ip + 1; sel_seg <= 1; seg_ea <= seg_cs; end
        8'h36: begin opcode <= bus; ip <= ip + 1; sel_seg <= 1; seg_ea <= seg_ss; end
        8'h3E: begin opcode <= bus; ip <= ip + 1; sel_seg <= 1; seg_ea <= seg_ds; end
        8'h64: begin opcode <= bus; ip <= ip + 1; sel_seg <= 1; seg_ea <= seg_fs; end
        8'h65: begin opcode <= bus; ip <= ip + 1; sel_seg <= 1; seg_ea <= seg_gs; end
        8'h66: begin opcode <= bus; ip <= ip + 1; opsize  <= ~opsize; end
        8'h67: begin opcode <= bus; ip <= ip + 1; adsize  <= ~adsize; end
        8'hF2: begin opcode <= bus; ip <= ip + 1; sel_rep <= 2'b10; end // REPNZ
        8'hF3: begin opcode <= bus; ip <= ip + 1; sel_rep <= 2'b11; end // REPZ
        8'h0F: begin opcode <= {1'b1, bus}; ip <= ip + 1; end

        // Неиспользуемые коды операции
        8'hF0, 8'h9B: begin opcode <= bus; ip <= ip + 1; end

        // ==== Групповые инструкции должны идти первыми ====

        // Групповые инструкции F6/F7
        8'b1111_011x: case (tstate)

            0: begin tstate <= 1; {idir, isize} <= opcode[0]; mode <= FETCHEA; end
            1: begin tstate <= 2; case (modrm[5:3])

                // TEST
                0, 1: begin sel <= 0; mode <= IMMEDIATE; end
                // NOT
                2:    begin wb  <= ~op1; mode <= SETEA; end
                // NEG
                3:    begin op1 <= 0; op2 <= op1; alumode <= 5; end
                // MUL
                4:    begin op2 <= isize ? (opsize ? eax : eax[15:0]) : eax[7:0]; end
                // IMUL
                5:    begin

                    op1 <= isize ? (opsize ? op1 : {{16{op1[15]}},op1[15:0]}) : {{24{op1[7]}},op1[7:0]};
                    op2 <= isize ? (opsize ? eax : {{16{eax[15]}},eax[15:0]}) : {{24{eax[7]}},eax[7:0]};

                end
                // DIV, IDIV
                6, 7: begin

                    divcnt <= isize ? (opsize ? 64 : 32) : 16;
                    diva   <= isize ? (opsize ? {edx, eax} : {edx[15:0],eax[15:0],32'h0}) : {eax[15:0],48'h0};
                    divb   <= isize ? (opsize ? op1 : op1[15:0]) : op1[7:0];
                    divrem <= 0;
                    divres <= 0;
                    signa  <= 0;
                    signb  <= 0;

                    // Переход к IDIV вместо DIV
                    if (modrm[3]) tstate <= 4; else mode <= DIVIDE;

                end

            endcase end
            2: begin tstate <= 3; case (modrm[5:3])

                0, 1: begin op2 <= wb; alumode <= 4; end
                2:    begin sel <= 0; mode <= PREPARE; end
                3:    begin wb <= result; flags <= flags_o; mode <= SETEA; end
                4, 5: begin

                    sel  <= 0;
                    mode <= PREPARE;

                    // CF,OF устанавливаются при переполнении
                    // ZF при нулевом результате
                    if (opsize && isize) begin // 32 bit

                        eax <= mult[31:0];
                        edx <= mult[63:32];
                        flags[ZF] <= mult[63:0] == 0;
                        flags[CF] <= edx != 0;
                        flags[OF] <= edx != 0;

                    end else if (isize) begin // 16 bit

                        eax[15:0] <= mult[15:0];
                        edx[15:0] <= mult[31:16];
                        flags[ZF] <= mult[31:0] == 0;
                        flags[CF] <= edx[15:0]  != 0;
                        flags[OF] <= edx[15:0]  != 0;

                    end else begin // 8 bit

                        eax[15:0] <= mult[15:0];
                        flags[ZF] <= mult[15:0] == 0;
                        flags[CF] <= eax[15:8]  != 0;
                        flags[OF] <= eax[15:8]  != 0;

                    end

                end
                6, 7: begin

                    sel  <= 0;
                    wb   <= 0;
                    mode <= PREPARE;

                    if (isize && opsize) begin

                        eax <= signd ? -divres[31:0] : divres[31:0];
                        edx <= divrem[31:0];

                        if (|divres[63:32] || divb[31:0] == 0) mode <= INTERRUPT;

                    end else if (isize) begin

                        eax[15:0] <= signd ? -divres[15:0] : divres[15:0];
                        edx[15:0] <= divrem[15:0];

                        if (|divres[31:16] || divb[15:0] == 0) mode <= INTERRUPT;

                    end else begin

                        eax[ 7:0] <= signd ? -divres[7:0] : divres[7:0];
                        eax[15:8] <= divrem[7:0];

                        if (|divres[15:8] || divb[7:0] == 0) mode <= INTERRUPT;

                    end

                end

            endcase end
            3: case (modrm[5:3])

                0, 1: begin flags <= flags_o; mode <= PREPARE; end
                3, 6: begin sel <= 0; mode <= PREPARE; end

            endcase

            // Коррекция IDIV
            4: begin

                signa <= diva[63];

                // Определение знака A
                if (diva[63]) begin

                    if (isize && opsize) diva        <= -diva;
                    else if (isize)      diva[63:32] <= -diva[63:32];
                    else                 diva[63:48] <= -diva[63:48];

                end

                // Определение знака A
                if (isize && opsize && divb[31]) begin signb <= 1; divb[31:0] <= -divb[31:0]; end
                else if (isize && divb[15])      begin signb <= 1; divb[15:0] <= -divb[15:0]; end
                else if (divb[7])                begin signb <= 1; divb[ 7:0] <= -divb[ 7:0]; end

                tstate <= 2;
                mode   <= DIVIDE;

            end

        endcase

        // Групповые инструкции #2 INC/DEC r8
        8'b1111_1110: case (tstate)

            0: begin tstate <= 1; mode <= FETCHEA; {idir, isize} <= 2'b00; end
            1: begin tstate <= 2; op2 <= 1; alumode <= modrm[3] ? 5 : 0; end
            2: begin tstate <= 3; wb <= result; flags <= {flags_o[11:1], 1'b0}; mode <= SETEA; end
            3: begin sel <= 0; mode <= PREPARE; end

        endcase

        // Групповые инструкции #3 Word/DWord
        8'b1111_1111: case (tstate)

            0: begin tstate <= 1; {idir, isize} <= 2'b01; mode <= FETCHEA; end
            1: begin tstate <= 2; case (modrm[5:3])

                // INC|DEC
                0, 1: begin op2 <= 1; alumode <= modrm[3] ? 5 : 0; end
                // CALL rm16
                2: begin wb <= ip; ip <= op1; mode <= PUSH; end
                // CALL far: Запись CS
                3: begin wb <= seg_cs; mode <= PUSH; op2 <= ea; tmp16 <= seg_ea; end
                // JMP rm16
                4: begin ip <= op1; sel <= 0; mode <= PREPARE; end
                // JMP far
                5: begin ip <= op1; ea <= ea + (opsize ? 4 : 2); sel <= 1; end
                // PUSH rm16
                6: begin wb <= op1; mode <= PUSH; end

            endcase end
            2: begin tstate <= 3; case (modrm[5:3])

                // INC|DEC
                0, 1: begin mode <= SETEA; wb <= result; flags <= {flags_o[11:1], 1'b0}; {idir, isize} <= 2'b01; end
                // CALL far: запись IP
                3: begin wb <= ip; ip <= op1; mode <= PUSH; end
                // JMP far
                5: begin wb <= bus; ea <= ea + 1; end
                2, 6: mode <= PREPARE;

            endcase end
            3: begin tstate <= 4; case (modrm[5:3])

                // INC|DEC
                0, 1: begin sel <= 0; mode <= PREPARE; end
                // CALL far
                3: begin sel <= 1; seg_ea <= op2; ea <= tmp16 + (opsize ? 4 : 2); end
                // JMP far
                5: begin wb[15:8] <= bus; mode <= LOADSEG; regn <= 1; end

            endcase end
            4: begin tstate <= 5; case (modrm[5:3])

                3: begin wb <= bus; ea <= ea + 1; end
                5: begin sel <= 0; mode <= PREPARE; end

            endcase end
            5: begin tstate <= 6; case (modrm[5:3])

                3: begin wb[15:8] <= bus; mode <= LOADSEG; regn <= 1; end

            endcase end
            5: case (modrm[5:3])

                3: begin sel <= 0; mode <= PREPARE; end

            endcase

        endcase

        // Arithmetic Grp
        8'b1000_00xx: case (tstate)

            // Прочесть байт modrm, найти ссылку на память
            0: begin tstate <= 1; mode <= FETCHEA; isize <= opcode[0]; idir <= 0; end

            // Запрос на получение второго операнда
            1: begin tstate <= 2; mode <= IMMEDIATE;

                alumode <= modrm[5:3];
                sel     <= 0;
                if (opcode[1:0] == 2'b11) isize <= 0;

            end
            // Распознание второго операнда
            2: begin

                tstate <= 3;
                op2    <= opcode[1:0] == 2'b11 ? (opsize ? {{24{wb[7]}},wb[7:0]} : {{8{wb[7]}},wb[7:0]}) : wb;
                isize  <= opcode[0];

            end
            // Запись результата
            3: begin

                tstate <= 4;
                mode  <= alumode == 7 ? PREPARE : SETEA;
                sel   <= alumode == 7 ? 0 : 1;
                wb    <= result;
                flags <= flags_o;
                if (alumode == 7) sel <= 0;

            end
            4: begin sel <= 0; mode <= PREPARE; end

        endcase

        // ALU modrm
        8'b00_xxx_0xx: case (tstate)

            0: begin tstate <= 1; mode  <= FETCHEA; {idir, isize} <= opcode[1:0]; alumode <= opcode[5:3]; end
            1: begin tstate <= 2; flags <= flags_o; if (alumode < 7) begin mode <= SETEA; wb <= result; end end
            2: begin mode <= PREPARE; sel <= 0; end

        endcase

        // ALU ac, #
        8'b00_xxx_10x: case (tstate)

            0: begin

                tstate  <= 1;
                mode    <= IMMEDIATE;
                alumode <= opcode[5:3];
                isize   <= opcode[0];
                op1     <= opcode[0] ? (opsize ? eax : eax[15:0]) : eax[7:0];

            end
            1: begin tstate <= 2; op2 <= wb; end
            2: begin tstate <= 3; flags <= flags_o;

                idir <= 1;
                mode <= alumode == 7 ? PREPARE : SETEA;
                wb   <= result;
                modrm[5:3] <= 0;

            end
            3: mode <= PREPARE;

        endcase

        // ==== Строковые инструкции ====

        // MOVSx
        8'b1010_010x: case (tstate)

            0: begin // Читать

                tstate  <= 1;
                isize   <= opcode[0];
                ea      <= esi[15:0];
                op1     <= 0;
                op2     <= opcode[0] ? (opsize ? 4 : 2) : 1;

                // Если REP и CX=0, то пропуск инструкции
                if (sel_rep && ecx[15:0] == 0) begin sel <= 0; mode <= PREPARE; end
                else begin sel <= 1; estate <= 4; mode <= FETCHEA; end

            end
            1: begin // Писать

                tstate  <= 2;
                estate  <= 0;
                seg_ea  <= seg_es;
                ea      <= edi[15:0];
                wb      <= op1;
                mode    <= SETEA;

            end
            2: begin // Инкременты

                sel  <= 0;
                mode <= PREPARE;

                esi[15:0] <= flags[DF] ? esi[15:0] - op2 : esi[15:0] + op2;
                edi[15:0] <= flags[DF] ? edi[15:0] - op2 : edi[15:0] + op2;

                if (sel_rep) begin ecx[15:0] <= ecx[15:0] - 1; ip <= ipstart; end

            end

        endcase

        // CMPSx
        8'b1010_011x: case (tstate)

            0: begin // Читать DS:SI

                tstate  <= 1;
                isize   <= opcode[0];
                ea      <= esi[15:0];
                op1     <= 0;
                tmp16   <= opcode[0] ? (opsize ? 4 : 2) : 1;
                alumode <= 7; // alu=CMP

                // Если REP и CX=0, то пропуск инструкции
                if (sel_rep && ecx[15:0] == 0)
                     begin sel <= 0; mode <= PREPARE; end
                else begin sel <= 1; mode <= FETCHEA; estate <= 4; end

            end
            1: begin // Читать ES:DI

                tstate  <= 2;
                estate  <= 4;
                idir    <= 1;
                seg_ea  <= seg_es;
                ea      <= edi[15:0];
                mode    <= FETCHEA;

            end
            2: begin // Инкременты

                sel   <= 0;
                mode  <= PREPARE;
                flags <= flags_o;

                esi[15:0] <= flags[DF] ? esi[15:0] - tmp16 : esi[15:0] + tmp16;
                edi[15:0] <= flags[DF] ? edi[15:0] - tmp16 : edi[15:0] + tmp16;

                // При CMPSx всегда проверяется REPZ/REPNZ
                // При любом REP должен быть декрементирован CX
                if (sel_rep) ecx[15:0] <= ecx[15:0] - 1;
                if (sel_rep && sel_rep[0] == flags_o[ZF]) ip <= ipstart;

            end

        endcase

        // STOSx
        8'b1010_101x: case (tstate)

            0: begin

                tstate  <= 1;
                isize   <= opcode[0];
                seg_ea  <= seg_es;
                ea      <= edi[15:0];
                wb      <= eax;
                op2     <= opcode[0] ? (opsize ? 4 : 2) : 1;

                // Если REP и CX=0, то пропуск инструкции
                if (sel_rep && ecx[15:0] == 0) mode <= PREPARE;
                else begin sel <= 1; mode <= SETEA; end

            end
            1: begin

                sel  <= 0;
                mode <= PREPARE;

                // Увеличить/Уменьшить DI
                edi[15:0] <= flags[DF] ? edi[15:0] - op2 : edi[15:0] + op2;

                // Если есть префикс REP: то повторить инструкцию
                if (sel_rep) begin ecx[15:0] <= ecx[15:0] - 1; ip <= ipstart; end

            end

        endcase

        // LODSx
        8'b1010_110x: case (tstate)

            0: begin

                tstate  <= 1;
                estate  <= 4;
                isize   <= opcode[0];
                ea      <= esi[15:0];
                op1     <= 0;
                op2     <= opcode[0] ? (opsize ? 4 : 2) : 1;

                // Если REP и CX=0, то пропуск инструкции
                if (sel_rep && ecx[15:0] == 0) mode <= PREPARE;
                else begin sel <= 1; mode <= FETCHEA; end

            end
            1: begin

                sel  <= 0;
                mode <= PREPARE;

                // Загрузка в Acc
                if (isize && opsize) eax <= op1;
                else if (isize) eax[15:0] <= op1[15:0];
                else eax[7:0] <= op1[7:0];

                esi[15:0] <= flags[DF] ? esi[15:0] - op2 : esi[15:0] + op2;
                if (sel_rep) begin ecx[15:0] <= ecx[15:0] - 1; ip <= ipstart; end

            end

        endcase

        // SCASx
        8'b1010_111x: case (tstate)

            0: begin // Читать ES:DI

                tstate  <= 1;
                idir    <= 1;
                isize   <= opcode[0];
                seg_ea  <= seg_es;
                ea      <= edi[15:0];
                op1     <= eax;
                tmp16   <= opcode[0] ? (opsize ? 4 : 2) : 1;
                alumode <= 7; // alu=CMP

                // Если REP и CX=0, то пропуск инструкции
                if (sel_rep && ecx[15:0] == 0)
                     begin sel <= 0; mode <= PREPARE; end
                else begin sel <= 1; mode <= FETCHEA; estate <= 4; end

            end
            1: begin // Инкременты

                sel   <= 0;
                mode  <= PREPARE;
                flags <= flags_o;

                edi[15:0] <= flags[DF] ? edi[15:0] - tmp16 : edi[15:0] + tmp16;

                // Учет префикса REP:
                if (sel_rep) ecx[15:0] <= ecx[15:0] - 1;
                if (sel_rep && sel_rep[0] == flags_o[ZF]) ip <= ipstart;

            end

        endcase

        // ==== Все инструкции ====

        // PUSH sr
        8'b00_0xx_110: case (tstate)

            0: begin tstate <= 1;

                mode <= PUSH;
                case (opcode[4:3])
                    2'b00: wb <= seg_es;
                    2'b01: wb <= seg_cs;
                    2'b10: wb <= seg_ss;
                    2'b11: wb <= seg_ds;
                endcase

            end

            1: mode <= PREPARE;

        endcase

        // POP sr
        8'b00_0xx_111: case (tstate)

            0: begin tstate <= 1; mode <= POP; end
            1: begin tstate <= 2; mode <= LOADSEG; regn <= opcode[4:3]; end
            2: mode <= PREPARE;

        endcase

        // DAA|DAS|AAA|AAS
        8'b00_1xx_111: case (tstate)

            0: begin tstate <= 1; op1 <= eax[15:0]; alumode <= opcode[4:3]; end
            1: begin mode <= PREPARE;

                flags <= flags_d;
                if (opcode[4])
                     eax[15:0] <= daa_r;
                else eax[ 7:0] <= daa_r[7:0];

            end

        endcase

        // INC|DEC r
        8'b01_00x_xxx: case (tstate)

            0: begin tstate <= 1; op2 <= 1;    regn <= opcode[2:0]; isize <= 1'b1; end
            1: begin tstate <= 2; op1 <= regv; alumode <= opcode[3] ? /*SUB*/ 5 : /*ADD*/ 0; end
            2: begin tstate <= 3;

                mode    <= SETEA;
                idir    <= 1'b1;
                wb      <= result;
                flags   <= {flags_o[11:1], flags[0]};
                modrm[5:3] <= regn;

            end
            3: mode <= PREPARE;

        endcase

        // PUSH r
        8'b01_010_xxx: case (tstate)

            0: begin tstate <= 1; regn <= opcode[2:0]; isize <= 1'b1; end
            1: begin tstate <= 2; wb   <= regv; mode <= PUSH; end
            2: mode <= PREPARE;

        endcase

        // POP r
        8'b01_011_xxx: case (tstate)

            0: begin tstate <= 1; mode <= POP;   {idir, isize} <= 2'b11; end
            1: begin tstate <= 2; mode <= SETEA; modrm[5:3] <= opcode[2:0]; end
            2: begin mode <= PREPARE; end

        endcase

        // Jccc b8
        8'b0111_xxxx: begin

            // Проверка на выполнение условия в branches
            if (branches[ opcode[3:1] ] ^ opcode[0])
                ip <= ip + 1 + {{8{bus[7]}}, bus[7:0]};
            else
                ip <= ip + 1;

            mode <= PREPARE;

        end

        // TEST rm, r
        8'b1000_010x: case (tstate)

            0: begin tstate <= 1; {idir, isize} <= opcode[1:0]; mode <= FETCHEA; alumode <= 4; end
            1: begin flags <= flags_o; sel <= 0; mode <= PREPARE; end

        endcase

        // XCHG rm, r
        8'b1000_011x: case (tstate)

            0: begin tstate <= 1; {idir, isize} <= opcode[1:0]; mode <= FETCHEA; alumode <= 4; end
            1: begin tstate <= 2; wb <= op2; mode <= SETEA; end
            2: begin tstate <= 3; wb <= op1; mode <= SETEA; idir <= 0; end
            3: begin sel <= 0; mode <= PREPARE; end

        endcase

        // MOV rmr
        8'b1000_10xx: case (tstate)

            0: begin tstate <= 1; {idir, isize} <= opcode[1:0]; mode <= FETCHEA; end
            1: begin tstate <= 2; wb <= op2; mode <= SETEA; end
            2: begin sel <= 0; mode <= PREPARE; end

        endcase

        // LEA r16, ea
        8'b1000_1101: case (tstate)

            0: begin tstate <= 1; {idir, isize} <= 2'b11; mode <= FETCHEA; skip_op <= 1; end
            1: begin tstate <= 2; wb <= ea; mode <= SETEA; end
            2: begin sel <= 0; mode <= PREPARE; end

        endcase

        // MOV sreg|rm
        8'b1000_11x0: case (tstate)

            0: begin tstate <= 1; {isize, idir} <= opcode[2:1]; skip_op <= ~opcode[1]; mode <= FETCHEA; end
            1: begin

                tstate <= 2;

                // MOV sr, r16
                if (opcode[1]) begin

                    mode <= LOADSEG;
                    regn <= modrm[5:3];
                    wb   <= op2;

                end
                // MOV rm, sr
                else begin

                    mode <= SETEA;
                    case (modrm[5:3])
                        0: wb <= seg_es;
                        1: wb <= seg_cs;
                        2: wb <= seg_ss;
                        3: wb <= seg_ds;
                        4: wb <= seg_fs;
                        5: wb <= seg_gs;
                    endcase

                end

            end
            2: begin sel <= 0; mode <= PREPARE; end

        endcase

        // POP rm
        8'b1000_1111: case (tstate)

            0: begin tstate <= 1; mode <= POP; {idir, isize} <= 2'b01; op1 <= seg_ea; end
            1: begin tstate <= 2; mode <= FETCHEA; skip_op <= 1;       seg_ea <= op1; end
            2: begin tstate <= 3; mode <= SETEA; end
            3: begin sel    <= 0; mode <= PREPARE; end

        endcase

        // XCHG ax, r
        8'b1001_0000: mode <= PREPARE;
        8'b1001_0xxx: case (tstate)

            0: begin tstate <= 1; regn <= opcode[2:0]; modrm[5:3] <= opcode[2:0]; {isize, idir} <= 2'b11; end
            1: begin tstate <= 2; mode <= SETEA; wb <= eax; if (opsize) eax <= regv; else eax[15:0] <= regv; end
            2: begin sel <= 0; mode <= PREPARE; end

        endcase

        // CBW, CWDE
        8'b1001_1000: begin

            if (opsize) eax[31:16] <= {16{eax[15]}};
            else        eax[15:8]  <= {8{eax[7]}};

            mode <= PREPARE;

        end

        // CWD, CDQ
        8'b1001_1001: begin

            if (opsize) edx       <= {32{eax[31]}};
            else        edx[15:0] <= {16{eax[15]}};

            mode <= PREPARE;

        end

        // CALL far
        8'b1001_1010: case (tstate)

            0: begin tstate <= 1; isize  <= 1; mode <= IMMEDIATE; end
            1: begin tstate <= 2; opsize <= 0; mode <= IMMEDIATE; op1 <= wb; end
            2: begin tstate <= 3; mode <= PUSH; wb <= seg_cs;     op2 <= wb;  end
            3: begin tstate <= 4; mode <= PUSH; wb <= ip; end
            4: begin tstate <= 5; mode <= LOADSEG; wb <= op2; regn <= 1; ip <= op1; end
            5: begin mode <= PREPARE; end

        endcase

        // PUSHF
        8'b1001_1100: case (tstate)

            0: begin tstate <= 1; mode <= PUSH; wb <= flags;  end
            1: begin sel <= 0; mode <= PREPARE; end

        endcase

        // POPF
        8'b1001_1101: case (tstate)

            0: begin tstate <= 1; mode <= POP; end
            1: begin flags <= wb[11:0]; sel <= 0; mode <= PREPARE; end

        endcase

        // SAHF, LAHF
        8'b1001_1110: begin flags[7:0] <= eax[15:8]; mode <= PREPARE; end
        8'b1001_1111: begin eax[15:8] <= flags[7:0]; mode <= PREPARE; end

        // MOV r,#
        8'b1011_xxxx: case (tstate)

            0: begin

                tstate  <= 1;
                idir    <= 1;
                isize   <= opcode[3];
                modrm[5:3] <= opcode[2:0];
                mode    <= IMMEDIATE;

            end
            1: begin tstate <= 2; mode <= SETEA; end
            2: mode <= PREPARE;

        endcase

        // MOV ac, [m16]
        8'b1010_00xx: case (tstate)

            0: begin // Чтение imm8/16/32

                tstate  <= 1;
                opsizet <= opsize;
                opsize  <= adsize;
                isize   <= 1;
                mode    <= IMMEDIATE;

            end
            1: begin // Запрос на чтение из памяти или запись в память

                tstate <= 2;
                sel    <= 1;
                modrm  <= 0;
                idir   <= 0;
                isize  <= opcode[0];
                opsize <= opsizet;
                ea     <= wb;

                // acc -> mem
                if (opcode[1]) begin mode <= SETEA; wb <= eax; end else
                // mem -> acc
                begin mode <= FETCHEA; sel <= 1; estate <= 4; end

            end
            2: begin // Запись в регистр ACC или выход

                sel  <= 0;
                mode <= PREPARE;

                // Запись в регистр AL, AX, EAX
                if (opcode[1] == 0) begin

                    if (isize && opsize) eax <= op1;
                    else if (isize)      eax[15:0] <= op1[15:0];
                    else eax[7:0] <= op1[7:0];

                end

            end

        endcase

        // TEST eax, #
        8'b1010_100x: case (tstate)

            0: begin tstate <= 1; isize <= opcode[0]; mode <= IMMEDIATE; end
            1: begin tstate <= 2; alumode <= 4; op1 <= eax; op2 = wb; end
            2: begin flags <= flags_o; sel <= 0; mode <= PREPARE; end

        endcase

        // RET [i16]
        8'b1100_001x: case (tstate)

            // Если opcode[0]=0, imm16
            0: begin tstate <= 1; isize <= 1; mode <= POP; end
            1: begin tstate <= 2; op1 <= wb; if (opcode[0] == 0) mode <= IMMEDIATE; end
            2: begin

                ip   <= op1;
                sel  <= 0;
                mode <= PREPARE;

                // Если RET imm, то добавить к стеку
                if (opcode[0] == 0) begin
                if (stack32) esp <= esp + wb; else esp[15:0] <= esp[15:0] + wb;
                end

            end

        endcase

        // LES|LDS r16, [m]
        8'b1100_010x: case (tstate)

            0: begin tstate <= 1; {idir, isize} <= 2'b11; mode <= FETCHEA; end
            1: begin tstate <= 2; mode <= SETEA; wb <= op2; end
            2: begin tstate <= 3; ea   <= ea + opsize ? 4 : 2; end
            3: begin tstate <= 4; wb[7:0]  <= bus; ea   <= ea + 1; end
            4: begin tstate <= 5; wb[15:8] <= bus; regn <= opcode[0] ? 3 : 0; mode <= LOADSEG; sel <= 0; end
            5: begin mode <= PREPARE; end

        endcase

        // MOV rm, #
        8'b1100_011x: case (tstate)

            0: begin tstate <= 1; {idir, isize} <= {1'b0, opcode[0]}; skip_op <= 1; mode <= FETCHEA; end
            1: begin tstate <= 2; sel <= 0; mode <= IMMEDIATE; end
            2: begin tstate <= 3; sel <= 1; mode <= SETEA; end
            3: begin sel <= 0; mode <= PREPARE; end

        endcase

        // RETF
        8'b1100_101x: case (tstate)

            0: begin tstate <= 1; isize <= 1; mode <= POP; end
            1: begin tstate <= 2; op1 <= wb;  mode <= POP; end
            2: begin tstate <= 3; op2 <= wb;  if (opcode[0] == 0) mode <= IMMEDIATE; end
            3: begin tstate <= 4;

                ip   <= op1;
                wb   <= op2;
                regn <= 1;
                sel  <= 0;
                mode <= LOADSEG;

                if (opcode[0] == 0) begin
                if (stack32) esp <= esp + wb; else esp[15:0] <= esp[15:0] + wb;
                end

            end
            4: mode <= PREPARE;

        endcase

        // INT 1/3
        8'b1111_0001,
        8'b1100_1100: case (tstate)

            0: begin tstate <= 1; wb <= opcode[0] ? 1 : 3; mode <= INTERRUPT; end
            1: begin mode <= PREPARE; end

        endcase

        // INT i8
        8'b1100_1101: case (tstate)

            0: begin tstate <= 1; isize <= 0; mode <= IMMEDIATE; end
            1: begin tstate <= 2; mode <= INTERRUPT; end
            2: begin mode <= PREPARE; end

        endcase

        // INTO: Вызов INT4 если OF=1
        8'b1100_1110: case (tstate)

            0: begin

                tstate <= 1;
                wb     <= 4;
                mode   <= flags[OF] ? INTERRUPT : PREPARE;

            end
            1: mode <= PREPARE;

        endcase

        // IRET
        8'b1100_1111: case (tstate)

            0: begin tstate <= 1; mode <= POP; end
            1: begin tstate <= 2; mode <= POP; op1 <= wb; end
            2: begin tstate <= 3; mode <= POP; op2 <= wb; end
            3: begin tstate <= 4; mode <= LOADSEG; regn <= 1; ip <= op1; wb <= op2; flags <= wb; end
            4: mode <= PREPARE;

        endcase

        // Сдвиговые инструкции (IMM)
        8'b1100_000x: case (tstate)

            0: begin tstate <= 1; mode <= FETCHEA; {idir, isize} <= opcode[1:0]; end
            1: begin tstate <= 2; mode <= IMMEDIATE; sel <= 0; isize <= 0; opsizet <= isize; end
            2: begin tstate <= 3; mode <= SHIFT; alumode <= modrm[5:3]; op2 <= wb; isize <= opsizet; end
            3: begin tstate <= 4; mode <= SETEA; sel <= 1; wb <= op1; end
            4: begin sel    <= 0; mode <= PREPARE;  end

        endcase

        // Сдвиговые инструкции (CL,N)
        8'b1101_00xx: case (tstate)

            0: begin tstate <= 1; mode <= FETCHEA; {idir, isize} <= {1'b0, opcode[0]}; end
            1: begin tstate <= 2; mode <= SHIFT; alumode <= modrm[5:3]; op2 <= opcode[1] ? ecx[4:0] : 1; end
            2: begin tstate <= 3; mode <= SETEA; wb <= op1; end
            3: begin sel    <= 0; mode <= PREPARE;  end

        endcase

        // AAM
        8'b1101_0100: case (tstate)

            0: begin tstate <= 1;

                divcnt  <= 8;
                diva    <= {eax[7:0], 56'b0};
                divb    <= bus;
                wb      <= 0;
                mode    <= bus ? DIVIDE : INTERRUPT;
                ip      <= ip + 1;

            end
            1: begin

                sel <= 0;
                mode <= PREPARE;

                if (divb) begin

                    eax[15:0] <= {divres[7:0], divrem[7:0]};
                    flags[ZF] <= eax[15:0] == 0;
                    flags[SF] <= eax[15];
                    flags[PF] <= ~^eax[15];

                end

            end

        endcase

        // AAD
        8'b1101_0101: case (tstate)

            0: begin tstate <= 1; eax[15:0] <= eax[15:8]*bus + eax[7:0]; ip <= ip + 1; end
            1: begin mode <= PREPARE;

                flags[ZF] <= eax[15:0] == 0;
                flags[SF] <= eax[15];
                flags[PF] <= ~^eax[15];

            end

        endcase

        // SALC
        8'b1101_0110: begin eax[7:0] <= {8{flags[CF]}}; mode <= PREPARE; end

        // XLATB
        8'b1101_0111: case (tstate)

            0: begin sel <= 1; tstate <= 1; ea <= ebx[15:0] + eax[7:0]; end
            1: begin sel <= 0; eax[7:0] <= bus; mode <= PREPARE; end

        endcase

        // JCXZ
        8'b1110_0011: begin

            mode <= PREPARE;
            if ((opsize && ecx == 0) || (!adsize && ecx[15:0] == 0))
                ip <= ip + 1 + {{24{bus[7]}}, bus[7:0]};
            else
                ip <= ip + 1;

        end

        // LOOPNZ, LOOPZ, LOOP
        8'b1110_00xx: begin

            if (adsize) ecx       <= ecx - 1;
            else        ecx[15:0] <= ecx[15:0] - 1;

            // ZF=0/1 и CX != 0 (после декремента)
            if (((flags[ZF] == opcode[0]) || opcode[1]) && (adsize ? ecx : ecx[15:0]) != 1)
                ip <= ip + 1 + {{24{bus[7]}}, bus[7:0]};
            else
                ip <= ip + 1;

            mode <= PREPARE;

        end

        // IN eAX, dx/i8
        8'b1110_x10x: case (tstate)

            0: begin tstate <= 1;

                if (opcode[3] == 0) ip <= ip + 1;
                port <= opcode[3] ? edx[15:0] : bus;
                op1  <= opcode[0] ? (opsize ? 3 : 1) : 0;
                op2  <= 0;

            end
            1: begin tstate <= 2; port_clk <= 1; end
            2: begin tstate <= 3; port_clk <= 0; end
            3: begin tstate <= 1;

                case (op2[1:0])

                    0: eax[7:0]   <= port_i;
                    1: eax[15:8]  <= port_i;
                    2: eax[23:16] <= port_i;
                    3: eax[31:24] <= port_i;

                endcase

                port     <= port + 1;
                op2[1:0] <= op2[1:0] + 1;

                if (op1[1:0] == op2[1:0]) mode <= PREPARE;

            end

        endcase

        // OUT dx/i8, eAX
        8'b1110_x11x: case (tstate)

            0: begin tstate <= 1;

                if (opcode[3] == 0) ip <= ip + 1;
                port <= opcode[3] ? edx[15:0] : bus;
                op1  <= opcode[0] ? (opsize ? 3 : 1) : 0;
                op2  <= 0;

            end
            1: begin tstate <= 2;

                case (op2[1:0])

                    0: port_o <= eax[7:0];
                    1: port_o <= eax[15:8];
                    2: port_o <= eax[23:16];
                    3: port_o <= eax[31:24];

                endcase

                port_w   <= 1;
                port_clk <= 1;

            end
            2: begin tstate <= 3; port_w <= 0; port_clk <= 0; end
            3: begin tstate <= 1;

                port     <= port + 1;
                op2[1:0] <= op2[1:0] + 1;

                if (op1[1:0] == op2[1:0]) mode <= PREPARE;

            end

        endcase

        // CALL b16
        8'b1110_1000: case (tstate)

            0: begin tstate <= 1; isize <= 1; mode <= IMMEDIATE; end
            1: begin tstate <= 2; wb <= ip; ip <= ip + wb; mode <= PUSH; end
            2: begin mode <= PREPARE; end

        endcase

        // JMP b16
        8'b1110_1001: case (tstate)

            0: begin tstate <= 1; isize <= 1; mode <= IMMEDIATE; end
            1: begin mode <= PREPARE; ip <= ip + wb; end

        endcase

        // JMP b16:c16
        8'b1110_1010: case (tstate)

            0: begin tstate <= 1; isize <= 1; mode <= IMMEDIATE; end
            1: begin tstate <= 2; op1 <= wb; opsize <= 0; mode <= IMMEDIATE; end
            2: begin tstate <= 3; mode <= LOADSEG; regn <= 1; ip <= op1; end
            3: begin mode <= PREPARE; end

        endcase

        // JMP b8
        8'b1110_1011: begin ip <= ip + 1 + {{8{bus[7]}}, bus[7:0]}; mode <= PREPARE; end

        // HLT
        8'b1111_0100: begin ip <= ip - 1; mode <= PREPARE; end

        // CMC, CLC, STC, CLI, STI, CLD, STD
        8'b1111_0101: begin flags[CF] <= ~flags[CF]; mode <= PREPARE; end
        8'b1111_100x: begin flags[CF] <= opcode[0];  mode <= PREPARE; end
        8'b1111_101x: begin flags[IF] <= opcode[0];  mode <= PREPARE; end
        8'b1111_110x: begin flags[DF] <= opcode[0];  mode <= PREPARE; end

        // Коды расширенных инструкции
        // =============================================================

        // Jccc NEAR b16
        9'b1_1000_xxxx: case (tstate)

            0: begin tstate <= 1; wb <= bus; ip <= ip + 1; end
            1: begin

                if (branches[opcode[3:1]] ^ opcode[0])
                    ip <= ip + (adsize ? 3 : 1) + {bus, wb[7:0]};
                else
                    ip <= ip + (adsize ? 3 : 1);

                mode <= PREPARE;

            end

        endcase

        // RDTSC
        9'b1_0011_0001: begin eax <= rdtsc[31:0]; edx <= rdtsc[63:32]; mode <= PREPARE; end

    endcase

    // Считывание эффективного адреса и регистров
    FETCHEA: case (estate)

        0: begin

            modrm <= bus;
            ip    <= ip + 1;

            // Операнд 1
            case (idir ? bus[5:3] : bus[2:0])

                0: op1 <= isize ? (opsize ? eax : eax[15:0]) : eax[ 7:0];
                1: op1 <= isize ? (opsize ? ecx : ecx[15:0]) : ecx[ 7:0];
                2: op1 <= isize ? (opsize ? edx : edx[15:0]) : edx[ 7:0];
                3: op1 <= isize ? (opsize ? ebx : ebx[15:0]) : ebx[ 7:0];
                4: op1 <= isize ? (opsize ? esp : esp[15:0]) : eax[15:8];
                5: op1 <= isize ? (opsize ? ebp : ebp[15:0]) : ecx[15:8];
                6: op1 <= isize ? (opsize ? esi : esi[15:0]) : edx[15:8];
                7: op1 <= isize ? (opsize ? edi : edi[15:0]) : ebx[15:8];

            endcase

            // Операнд 2
            case (idir ? bus[2:0] : bus[5:3])

                0: op2 <= isize ? (opsize ? eax : eax[15:0]) : eax[ 7:0];
                1: op2 <= isize ? (opsize ? ecx : ecx[15:0]) : ecx[ 7:0];
                2: op2 <= isize ? (opsize ? edx : edx[15:0]) : edx[ 7:0];
                3: op2 <= isize ? (opsize ? ebx : ebx[15:0]) : ebx[ 7:0];
                4: op2 <= isize ? (opsize ? esp : esp[15:0]) : eax[15:8];
                5: op2 <= isize ? (opsize ? ebp : ebp[15:0]) : ecx[15:8];
                6: op2 <= isize ? (opsize ? esi : esi[15:0]) : edx[15:8];
                7: op2 <= isize ? (opsize ? edi : edi[15:0]) : ebx[15:8];

            endcase

            // Вычисление эффективного адреса 32 bit
            if (adsize)
            case (bus[2:0])
                0: ea <= eax;
                1: ea <= ecx;
                2: ea <= edx;
                3: ea <= ebx;
                // 4: SIB
                5: ea <= ebp;
                6: ea <= esi;
                7: ea <= edi;
            endcase
            else
            // Вычисление эффективного адреса 16 bit
            case (bus[2:0])

                0: ea[15:0] <= ebx[15:0] + esi[15:0];
                1: ea[15:0] <= ebx[15:0] + edi[15:0];
                2: ea[15:0] <= ebp[15:0] + esi[15:0];
                3: ea[15:0] <= ebp[15:0] + edi[15:0];
                4: ea[15:0] <= esi[15:0];
                5: ea[15:0] <= edi[15:0];
                6: ea[15:0] <= ebp[15:0];
                7: ea[15:0] <= ebx[15:0];

            endcase

            // Выбор SS: по умолчанию
            if (!sel_seg) begin

                // 32 bit
                if (adsize) begin if (bus[2:0] == 5 && ^bus[7:6]) seg_ea <= seg_ss; end
                // 16 bit
                else if ((bus[2:0] == 3'h6 && ^bus[7:6]) || (bus[2:1] == 2'b01))
                    seg_ea <= seg_ss;
            end

            // 32 bit
            if (adsize)
            casex (bus)

                8'b11_xxx_xxx: begin estate <= 0; mode <= MAIN; end // reg
                8'b00_xxx_101: begin estate <= 8; ea <= 0; end      // disp32
                8'bxx_xxx_100: begin estate <= 12; end              // sib
                8'b00_xxx_xxx: begin estate <= 4; sel <= 1; end     // без disp
                8'b01_xxx_xxx: begin estate <= 3; end               // disp8
                8'b10_xxx_xxx: begin estate <= 8; end               // disp32

            endcase
            // 16 bit
            else casex (bus)

                8'b00_xxx_110: begin estate <= 1; ea  <= 0; end // disp16
                8'b00_xxx_xxx: begin estate <= 4; sel <= 1; end // без disp
                8'b01_xxx_xxx: begin estate <= 3; end           // disp8
                8'b10_xxx_xxx: begin estate <= 1; end           // disp16
                8'b11_xxx_xxx: begin estate <= 0; mode <= MAIN; end

            endcase

        end

        // Считывание 16-бит displacement
        1: begin estate <= 2; ip <= ip + 1; ea <= ea + bus; end
        2: begin estate <= 4; ip <= ip + 1; ea[15:8] <= ea[15:8] + bus; ea[31:16] <= 0; sel <= 1; end

        // Считывание 8-бит displacement
        3: begin estate <= 4;

            ip  <= ip + 1;
            sel <= 1;

            if (adsize)
                 ea <= ea + {{24{bus[7]}}, bus[7:0]};
            else ea[15:0] <= ea[15:0] + {{8{bus[7]}}, bus[7:0]};

        end

        // Чтение операнда 8bit из памяти
        4: begin

            if (skip_op) begin estate <= 0; mode <= MAIN; end
            else begin

                if (idir) op2 <= bus; else op1 <= bus;
                if (isize) begin estate <= 5; ea <= ea + 1; end
                else       begin estate <= 0; mode <= MAIN; end
            end

        end

        // Чтение операнда 16 бит (память)
        5: begin

            if (idir) op2[15:8] <= bus; else op1[15:8] <= bus;
            if (opsize) begin estate <= 6; ea <= ea + 1; end
            else        begin estate <= 0; ea <= ea - 1; mode <= MAIN; end

        end

        // Чтение операнда 32 бит (память)
        6: begin estate <= 7; if (idir) op2[23:16] <= bus; else op1[23:16] <= bus; ea <= ea + 1; end
        7: begin estate <= 0; if (idir) op2[31:24] <= bus; else op1[31:24] <= bus; ea <= ea - 3; mode <= MAIN; end

        // Чтение +disp32 и переход к чтение операнда из памяти
        8:  begin tstate <= 9;  ip <= ip + 1; ea        <= ea        + bus; end
        9:  begin tstate <= 10; ip <= ip + 1; ea[31:8]  <= ea[31:8]  + bus; end
        10: begin tstate <= 11; ip <= ip + 1; ea[31:16] <= ea[31:16] + bus; end
        11: begin tstate <= 4;  ip <= ip + 1; ea[31:24] <= ea[31:24] + bus; sel <= 1; end

        // Разбор байта SIB: Считывание SS*INDEX
        12: begin

            estate <= 13;

            casex (bus)

                8'bxx_000_xxx: ea <= eax << bus[7:6];
                8'bxx_001_xxx: ea <= ecx << bus[7:6];
                8'bxx_010_xxx: ea <= edx << bus[7:6];
                8'bxx_011_xxx: ea <= ebx << bus[7:6];
                8'bxx_100_xxx: ea <= 0;
                8'bxx_101_xxx: ea <= ebp << bus[7:6];
                8'bxx_110_xxx: ea <= esi << bus[7:6];
                8'bxx_111_xxx: ea <= edi << bus[7:6];

            endcase

            // Выбор сегмента SS: по умолчанию
            if (!sel_seg && bus[5:3] == 5) seg_ea <= seg_ss;

        end

        // Считывание BASE
        13: begin

            estate <= 4;
            sel    <= 1;
            ip     <= ip + 1;

            case (bus)

                // disp32
                8'bxx_xxx_000: ea <= ea + eax;
                8'bxx_xxx_001: ea <= ea + ecx;
                8'bxx_xxx_010: ea <= ea + edx;
                8'bxx_xxx_011: ea <= ea + ebx;
                8'bxx_xxx_100: ea <= ea + esp;
                8'bxx_xxx_101:
                if (^modrm[7:6]) begin
                    ea <= ea + ebp;
                    if (!sel_seg) seg_ea <= seg_ss;
                end
                8'bxx_xxx_110: ea <= ea + esi;
                8'bxx_xxx_111: ea <= ea + edi;

            endcase

            // +disp8/32
            if (modrm[7:6] == 2'b00 && bus[2:0] == 5) begin sel <= 0; estate <= 8; end
            else if (modrm[7:6] == 2'b01) begin sel <= 0; estate <= 3; end
            else if (modrm[7:6] == 2'b10) begin sel <= 0; estate <= 8; end

        end

    endcase

    // Запись обратно в память или регистр [idir, isize, modrm, wb]
    // * idir  (1 запись `wb` в регистр modrm[5:3])
    //         (0 запись в память ea)
    // * isize (0/1)
    // * wb    (8/16)
    SETEA: case (estate)

        0: begin

            // Запись результата в регистр
            if (idir || (modrm[7:6] == 2'b11)) begin

                case (idir ? modrm[5:3] : modrm[2:0])

                    0: if (isize && opsize) eax <= wb; else if (isize) eax[15:0] <= wb; else eax[ 7:0] <= wb[7:0];
                    1: if (isize && opsize) ecx <= wb; else if (isize) ecx[15:0] <= wb; else ecx[ 7:0] <= wb[7:0];
                    2: if (isize && opsize) edx <= wb; else if (isize) edx[15:0] <= wb; else edx[ 7:0] <= wb[7:0];
                    3: if (isize && opsize) ebx <= wb; else if (isize) ebx[15:0] <= wb; else ebx[ 7:0] <= wb[7:0];
                    4: if (isize && opsize) esp <= wb; else if (isize) esp[15:0] <= wb; else eax[15:8] <= wb[7:0];
                    5: if (isize && opsize) ebp <= wb; else if (isize) ebp[15:0] <= wb; else ecx[15:8] <= wb[7:0];
                    6: if (isize && opsize) esi <= wb; else if (isize) esi[15:0] <= wb; else edx[15:8] <= wb[7:0];
                    7: if (isize && opsize) edi <= wb; else if (isize) edi[15:0] <= wb; else ebx[15:8] <= wb[7:0];

                endcase

                mode <= MAIN;

            end
            // Запись [7:0] в память
            else begin

                estate <= 1;
                wreq   <= 1;
                data   <= wb[7:0];

            end

        end

        // Запись [15:8] или завершение
        1: begin

            if (isize)
                 begin estate <= 2; data <= wb[15:8]; ea <= ea + 1; end
            else begin estate <= 0; wreq <= 0; mode <= MAIN; end

        end

        // Завершение записи 16 bit
        2: begin

            if (opsize) begin estate <= 3; data <= wb[23:16]; ea <= ea + 1; end
            else        begin estate <= 0; wreq <= 0; mode <= MAIN; ea <= ea - 1; end

        end

        // Завершение записи 32 bit
        3: begin estate <= 4; data <= wb[31:24]; ea <= ea + 1; end
        4: begin estate <= 0; wreq <= 0; mode <= MAIN; ea <= ea - 3; end

    endcase

    // Получение imm8/16/32 [isize]
    IMMEDIATE: case (estate)

        0: begin ip <= ip + 1; wb        <= bus; if (isize == 0) mode <= MAIN; else begin estate <= 1; end end
        1: begin ip <= ip + 1; wb[ 15:8] <= bus; if (opsize) estate <= 2; else begin estate <= 0; mode <= MAIN; end end
        2: begin ip <= ip + 1; wb[23:16] <= bus; estate <= 3; end
        3: begin ip <= ip + 1; wb[31:24] <= bus; estate <= 0; mode <= MAIN; end

    endcase

    // Сохранение данных в стек [wb]
    // Если стек 32-х разрядный, используются 4 байта
    PUSH: case (estate)

        0: begin

            estate  <= 1;
            sel     <= 1;
            wreq    <= 1;
            seg_ea  <= seg_ss;
            data    <= wb[7:0];

            if (stack32) begin
                ea  <= esp - 4;
                esp <= esp - 4;
            end
            else begin
                ea        <= esp[15:0] - (opsize ? 4 : 2);
                esp[15:0] <= esp[15:0] - (opsize ? 4 : 2);
            end

        end
        1: begin estate <= 2; ea <= ea + 1; data <= wb[15:8]; end
        2: begin

            if (opsize) begin ea <= ea + 1; data <= wb[23:16]; estate <= 3; end
            else begin

                estate <= 0;
                sel    <= 0;
                wreq   <= 0;
                mode   <= MAIN;

            end

        end
        3: begin estate <= 4; ea <= ea + 1; data <= wb[31:24];  end
        4: begin estate <= 0; sel <= 0; wreq <= 0; mode <= MAIN; end

    endcase

    // Извлечение данных из стека -> wb
    POP: case (estate)

        0: begin

            estate  <= 1;
            sel     <= 1;
            seg_ea  <= seg_ss;

            if (stack32) begin
                ea  <= esp;
                esp <= esp - 4;
            end
            else begin
                ea        <= esp[15:0];
                esp[15:0] <= esp[15:0] + (opsize ? 4 : 2);
            end

        end
        1: begin estate <= 2; wb <= bus; ea <= ea + 1; end
        2: begin

            wb[15:8] <= bus;

            if (opsize) begin estate <= 3; ea <= ea + 1; end
            else        begin estate <= 0; sel <= 0; mode <= MAIN; end

        end
        3: begin estate <= 4; wb[23:16] <= bus; ea <= ea + 1; end
        4: begin estate <= 0; wb[31:24] <= bus; sel <= 0; mode <= MAIN; end

    endcase

    // Загрузка и проверка нового сегментного регистра [regn, wb]
    LOADSEG: case (estate)

        0: begin

            // Если это было прерывание
            if (is_intr) begin mode <= PREPARE; end
            else mode <= MAIN;

            case (regn)

                3'b000: seg_es <= wb;
                3'b001: seg_cs <= wb;
                3'b010: seg_ss <= wb;
                3'b011: seg_ds <= wb;
                3'b100: seg_fs <= wb;
                3'b101: seg_gs <= wb;

            endcase

        end

    endcase

    // Вызов прерывания [wb]
    INTERRUPT: case (estate)

        // Запись в стек CS:IP:FLAGS
        0: begin

            estate  <= 1;
            sel     <= 1;
            wreq    <= 1;
            seg_ea  <= seg_ss;
            data    <= ip[7:0];

            if (stack32) begin
                ea  <= esp - 4*3;
                esp <= esp - 4*3;
            end
            else begin
                ea        <= esp[15:0] - 2*3;
                esp[15:0] <= esp[15:0] - 2*3;
            end

        end
        1: begin data <= ip[15:8]; estate <= stack32 ? 2 : 4; ea <= ea + 1; end
        // 2, 3
        4: begin data <= seg_cs[ 7:0]; estate <= 5; ea <= ea + 1; end
        5: begin data <= seg_cs[15:8]; estate <= stack32 ? 6 : 8; ea <= ea + 1; end
        // 6, 7
        8: begin data <= flags[7:0]; estate <= 9; ea <= ea + 1; end
        9: begin data <= flags[11:8]; estate <= stack32 ? 10 : 12; ea <= ea + 1; end
        // 10, 11
        12: begin estate <= 13;

            wreq      <= 0;
            flags[IF] <= 1'b0;
            flags[TF] <= 1'b0;
            seg_ea    <= 0;
            ea        <= {wb, 2'b00};

        end
        // Загрузка нового CS:IP из IVT
        13: begin estate <= 14; ip[7:0]  <= bus; ea <= ea + 1; end
        14: begin estate <= 15; ip[15:8] <= bus; ea <= ea + 1; end
        15: begin estate <= 16; wb[7:0]  <= bus; ea <= ea + 1; end
        16: begin estate <= 0;  wb[15:8] <= bus; sel <= 0; regn <= 1; mode <= LOADSEG; end

        // 32-х битный
        default: begin estate <= estate + 1; data <= 0; ea <= ea + 1; end

    endcase

    // Сдвиги:
    // * alumode=операция
    // * isize, opsize
    // * op1
    // * op2
    SHIFT: case (estate)

        // Вычисление ограничения количества сдвигов
        0: begin

            estate <= 1;

            if (opsize && isize)
                begin wb <= 31; op2 <= op2[4:0]; end
            else if (isize)
                begin wb <= 15; op2 <= op2[3:0]; end
            else
                begin wb <= 7;  op2 <= op2[2:0]; end

        end

        // Вычисление
        1: begin

            // Сдвиги
            if (op2) begin

                op2 <= op2 - 1;
                case (alumode)

                    /* ROL */ 0:
                    begin op1 <= isize ? (opsize ? {op1[30:0],op1[31]} : {op1[14:0],op1[15]}) : {op1[6:0],op1[7]}; end

                    /* ROR */ 1:
                    begin op1 <= isize ? (opsize ? {op1[0],op1[31:1]} : {op1[0],op1[15:1]}) : {op1[0],op1[7:1]}; end

                    /* RCL */ 2:
                    begin

                        op1 <= isize ? (opsize ? {op1[30:0],flags[CF]} : {op1[14:0],flags[CF]}) : {op1[6:0],flags[CF]};
                        flags[CF] <= op1[wb];

                    end

                    /* RCR */ 3:
                    begin

                        op1 <= isize ? (opsize ? {flags[CF],op1[31:1]} : {flags[CF],op1[15:1]}) : {flags[CF],op1[7:1]};
                        flags[CF] <= op1[0];

                    end

                    /* SHL */ 4, 6:
                    begin

                        flags[CF] <= op1[wb-op2+1];
                        op1 <= op1 << op2;
                        op2 <= 0;

                    end
                    /* SHR */ 5:
                    begin

                        flags[CF] <= op1[op2-1];
                        op1 <= op1 >> op2;
                        op2 <= 0;

                    end

                    /* SAR */ 7:
                    begin
                        op1 <= isize ? (opsize ? {op1[31],op1[31:1]} : {op1[15],op1[15:1]}) : {op1[7],op1[7:1]};
                        flags[CF] <= op1[0];
                    end

                endcase

            end
            // Расчет флагов
            else begin

                estate <= 0;
                mode   <= MAIN;

                case (alumode)

                    0: begin flags[CF] <= op1[0];  flags[OF] <= op1[0]  ^ op1[wb];   end
                    1: begin flags[CF] <= op1[wb]; flags[OF] <= op1[wb] ^ op1[wb-1]; end
                    2: begin flags[OF] <= flags[CF] ^ op1[wb]; end
                    3: begin flags[OF] <= op1[wb] ^ op1[wb-1]; end
                    default: begin

                        flags[ZF] <= !op1;
                        flags[SF] <= op1[wb];
                        flags[PF] <= ~^op1[7:0];
                        flags[AF] <= 1;

                    end

                endcase

            end
        end

    endcase

    // Процедура деления [diva, divb, divcnt]
    DIVIDE: begin

        if (divcnt) begin

            divrem <= {divrem,diva[63]} >= divb ? {divrem,diva[63]} - divb : {divrem,diva[63]};
            divres <= {divres[62:0], {divrem,diva[63]} >= divb};
            diva   <= {diva[62:0], 1'b0};
            divcnt <= divcnt - 1;

        end
        else mode <= MAIN;

    end

endcase

endmodule
