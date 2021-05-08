module core88
(
    input   wire        clock,
    input   wire        resetn,
    input   wire        locked,
    output  wire [19:0] address,
    input   wire [ 7:0] bus,
    output  reg  [ 7:0] data,
    output  reg         wreq
);

`include "decl.v"

wire __m0 = (main == PREPARE);

// Выбор источника памяти
assign address = sel ? {seg_ea, 4'h0} + ea : {seg_cs, 4'h0} + ip;

// =====================================================================
// Основная работа процессорного микрокода, так сказать
// =====================================================================

always @(posedge clock)
// Сброс
if (resetn == 0) begin seg_cs <= 16'hF000; ip <= 0; main <= PREPARE; end
// Исполнение
else if (locked) case (main)

    // Считывание опкода, сброс, прерывания
    PREPARE: begin

        opcode  <= bus;
        ip      <= ip + 1;
        idir    <= 0;
        isize   <= 0;
        opsize  <= 0;
        adsize  <= 0;
        sel_seg <= 0;
        sel_rep <= 0;
        stack32 <= 0;
        seg_ea  <= seg_ds;
        tstate  <= 0;
        main    <= MAIN;

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
        8'hF2: begin opcode <= bus; ip <= ip + 1; sel_rep <= 1; end
        8'hF3: begin opcode <= bus; ip <= ip + 1; sel_rep <= 2; end

        // Неиспользуемые коды операции
        8'h0F, 8'hF0, 8'h9B: begin opcode <= bus; ip <= ip + 1; end

        // ALU modrm
        8'b00_xxx_0xx: case (tstate)

            0: begin tstate <= 1; main  <= FETCHEA; {idir, isize} <= opcode[1:0]; alumode <= opcode[5:3]; end
            1: begin tstate <= 2; flags <= flags_o; if (alumode < 7) begin main <= SETEA; wb <= result; end end
            2: begin main <= PREPARE; sel <= 0; end

        endcase

        // ALU ac, #
        8'b00_xxx_10x: case (tstate)

            0: begin

                tstate  <= 1;
                main    <= IMMEDIATE;
                isize   <= opcode[0];
                alumode <= opcode[5:3];
                op1     <= opsize ? eax : eax[15:0];

            end
            1: begin tstate <= 2; op2 <= wb; end
            2: begin tstate <= 3; flags <= flags_o;

                idir <= 1;
                main <= alumode == 7 ? PREPARE : SETEA;
                wb   <= result;
                modrm[5:3] <= 0;

            end
            3: main <= PREPARE;

        endcase

        // PUSH sr
        8'b00_0xx_110: case (tstate)

            0: begin tstate <= 1;

                main <= PUSH;
                case (opcode[4:3])
                    2'b00: wb <= seg_es;
                    2'b01: wb <= seg_cs;
                    2'b10: wb <= seg_ss;
                    2'b11: wb <= seg_ds;
                endcase

            end

            1: main <= PREPARE;

        endcase

        // POP sr
        8'b00_0xx_111: case (tstate)

            0: begin tstate <= 1; main <= POP; end
            1: begin tstate <= 2; main <= LOADSEG; regn <= opcode[4:3]; end
            2: main <= PREPARE;

        endcase

        // DAA|DAS|AAA|AAS
        8'b00_1xx_111: case (tstate)

            0: begin tstate <= 1; op1 <= eax[15:0]; alumode <= opcode[4:3]; end
            1: begin main <= PREPARE; flags <= flags_d; eax[7:0] <= daa_r; end

        endcase

        // INC|DEC r
        8'b01_00x_xxx: case (tstate)

            0: begin tstate <= 1; op2 <= 1;    regn <= opcode[2:0]; isize <= 1'b1; end
            1: begin tstate <= 2; op1 <= regv; alumode <= opcode[3] ? /*SUB*/ 5 : /*ADD*/ 0; end
            2: begin tstate <= 3;

                main    <= SETEA;
                idir    <= 1'b1;
                wb      <= result;
                flags   <= {flags_o[11:1], flags[0]};
                modrm[5:3] <= regn;

            end
            3: main <= PREPARE;

        endcase

        // PUSH r
        8'b01_010_xxx: case (tstate)

            0: begin tstate <= 1; regn <= opcode[2:0]; isize <= 1'b1; end
            1: begin tstate <= 2; wb   <= regv; main <= PUSH; end
            2: main <= PREPARE;

        endcase

        // POP r
        8'b01_011_xxx: case (tstate)

            0: begin tstate <= 1; main <= POP;   {idir, isize} <= 2'b11; end
            1: begin tstate <= 2; main <= SETEA; modrm[5:3] <= opcode[2:0]; end
            2: begin main <= PREPARE; end

        endcase

        // Jccc b8
        8'b0111_xxxx: begin

            // Проверка на выполнение условия в branches
            if (branches[ opcode[3:1] ] ^ opcode[0])
                ip <= ip + 1 + {{8{bus[7]}}, bus[7:0]};
            else
                ip <= ip + 1;

            main <= PREPARE;

        end

        // Arithmetic grp
        8'b1000_00xx: case (tstate)

            // Прочесть байт modrm, найти ссылку на память
            0: begin tstate <= 1; main <= FETCHEA; isize <= opcode[0]; idir <= 0; end

            // Запрос на получение второго операнда
            1: begin tstate <= 2; main <= IMMEDIATE;

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

                main  <= alumode == 7 ? PREPARE : SETEA;
                wb    <= result;
                flags <= flags_o;
                tstate <= 4;
                if (alumode == 7) sel <= 0;

            end
            4: begin sel <= 0; main <= PREPARE; end

        endcase

        // MOV rmr
        8'b1000_10xx: case (tstate)

            0: begin tstate <= 1; {idir, isize} <= opcode[1:0]; main <= FETCHEA; end
            1: begin tstate <= 2; wb <= op2; main <= SETEA; end
            2: begin sel <= 0; main <= PREPARE; end

        endcase

        // MOV sreg|rm
        8'b1000_11x0: case (tstate)

            0: begin tstate <= 1; idir <= opcode[1]; isize <= 1; main <= FETCHEA; end
            1: begin

                tstate <= 2;

                // MOV sr, r16
                if (opcode[1]) begin

                    main <= LOADSEG;
                    regn <= modrm[5:3];
                    wb   <= op2;

                end
                // MOV rm, sr
                else begin

                    main <= SETEA;
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
            2: begin sel <= 0; main <= PREPARE; end

        endcase

        // XCHG ax, r
        8'b1001_0000: main <= PREPARE;
        8'b1001_0xxx: case (tstate)

            0: begin tstate <= 1; regn <= opcode[2:0]; modrm[5:3] <= opcode[2:0]; {isize, idir} <= 2'b11; end
            1: begin tstate <= 2; main <= SETEA; wb <= eax; if (opsize) eax <= regv; else eax[15:0] <= regv; end
            2: begin sel <= 0; main <= PREPARE; end

        endcase

        // MOV r,#
        8'b1011_xxxx: case (tstate)

            0: begin

                tstate <= 1;
                idir   <= 1;
                isize  <= opcode[3];
                modrm[5:3] <= opcode[2:0];
                main   <= IMMEDIATE;

            end
            1: begin tstate <= 2; main <= SETEA; end
            2: main <= PREPARE;

        endcase

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

                0: ea <= ebx[15:0] + esi[15:0];
                1: ea <= ebx[15:0] + edi[15:0];
                2: ea <= ebp[15:0] + esi[15:0];
                3: ea <= ebp[15:0] + edi[15:0];
                4: ea <= esi[15:0];
                5: ea <= edi[15:0];
                6: ea <= ebp[15:0];
                7: ea <= ebx[15:0];

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

                8'b11_xxx_xxx: begin estate <= 0; main <= MAIN; end // reg
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
                8'b11_xxx_xxx: begin estate <= 0; main <= MAIN; end

            endcase

        end

        // Считывание 16-бит displacement
        1: begin estate <= 2; ip <= ip + 1; ea <= ea + bus; end
        2: begin estate <= 4; ip <= ip + 1; ea[15:8] <= ea[15:8] + bus; sel <= 1; end

        // Считывание 8-бит displacement
        3: begin estate <= 4;

            ip  <= ip + 1;
            sel <= 1;
            
            if (adsize)
                 ea <= ea + {{24{bus[7]}}, bus[7:0]};
            else ea <= ea[15:0] + {{8{bus[7]}}, bus[7:0]};
            
        end

        // Чтение операнда 8bit из памяти
        4: begin

            if (idir) op2 <= bus; else op1 <= bus;
            if (isize) begin estate <= 5; ea <= ea + 1; end
            else       begin estate <= 0; main <= MAIN; end

        end

        // Чтение операнда 16 бит (память)
        5: begin

            if (idir) op2[15:8] <= bus; else op1[15:8] <= bus;
            if (opsize) begin estate <= 6; ea <= ea + 1; end
            else        begin estate <= 0; ea <= ea - 1; main <= MAIN; end

        end

        // Чтение операнда 32 бит (память)
        6: begin estate <= 7; if (idir) op2[23:16] <= bus; else op1[23:16] <= bus; ea <= ea + 1; end
        7: begin estate <= 0; if (idir) op2[31:24] <= bus; else op1[31:24] <= bus; ea <= ea - 3; main <= MAIN; end

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

    // Запись обратно в память или регистр [idir, isize, wb, modrm]
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

                main <= MAIN;

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
            else begin estate <= 0; wreq <= 0; main <= MAIN; end

        end

        // Завершение записи 16 bit
        2: begin

            if (opsize) begin estate <= 3; data <= wb[23:16]; ea <= ea + 1; end
            else        begin estate <= 0; wreq <= 0; main <= MAIN; ea <= ea - 1; end

        end

        // Завершение записи 32 bit
        3: begin estate <= 4; data <= wb[31:24]; ea <= ea + 1; end
        4: begin estate <= 0; wreq <= 0; main <= MAIN; ea <= ea - 3; end

    endcase

    // Получение imm8/16/32
    IMMEDIATE: case (estate)

        0: begin ip <= ip + 1; wb        <= bus; if (isize == 0) main <= MAIN; else begin estate <= 1; end end
        1: begin ip <= ip + 1; wb[ 15:8] <= bus; if (opsize) estate <= 2; else begin estate <= 0; main <= MAIN; end end
        2: begin ip <= ip + 1; wb[23:16] <= bus; estate <= 3; end
        3: begin ip <= ip + 1; wb[31:24] <= bus; estate <= 0; main <= MAIN; end

    endcase

    // Сохранение данных в стек
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
                main   <= MAIN;
                
            end

        end
        3: begin estate <= 4; ea <= ea + 1; data <= wb[31:24];  end
        4: begin estate <= 0; sel <= 0; wreq <= 0; main <= MAIN; end

    endcase

    // Извлечение данных из стека
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
            else        begin estate <= 0; sel <= 0; main <= MAIN; end

        end
        3: begin estate <= 4; wb[23:16] <= bus; ea <= ea + 1; end
        4: begin estate <= 0; wb[31:24] <= bus; sel <= 0; main <= MAIN; end

    endcase

    // Загрузка и проверка нового сегментного регистра
    LOADSEG: case (estate)

        0: begin

            main <= MAIN;
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

    // INTERRUPT

endcase

endmodule
