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

// Выбор источника памяти
assign address = sel ? {seg_ea, 4'h0} + ea : {seg_cs, 4'h0} + ip;

// =====================================================================
// Основная работа процессорного микрокода, так сказать
// =====================================================================

always @(posedge clock)
// Сброс
if (resetn == 0) begin seg_cs <= 16'hF000; ip <= 0; end
// Исполнение
else if (locked) case (main)

    // Считывание опкода, сброс, прерывания
    PREPARE: begin

        opcode  <= bus;
        ip      <= ip + 1;
        sel_seg <= 0;
        sel_rep <= 0;
        seg_ea  <= seg_ds;
        main    <= MAIN;
        tstate  <= 0;

    end

    // Исполнение инструкции
    MAIN: begin

        casex (opcode)

            // ПРЕФИКСЫ:
            8'h26: begin opcode <= bus; ip <= ip + 1; sel_seg <= 1; seg_ea <= seg_es; end
            8'h2E: begin opcode <= bus; ip <= ip + 1; sel_seg <= 1; seg_ea <= seg_cs; end
            8'h36: begin opcode <= bus; ip <= ip + 1; sel_seg <= 1; seg_ea <= seg_ss; end
            8'h3E: begin opcode <= bus; ip <= ip + 1; sel_seg <= 1; seg_ea <= seg_ds; end
            8'hF2: begin opcode <= bus; ip <= ip + 1; sel_rep <= 1; end
            8'hF3: begin opcode <= bus; ip <= ip + 1; sel_rep <= 2; end
            // Неиспользуемые префиксы
            8'h0F, 8'hF0, 8'h64, 8'h65, 8'h66, 8'h67: begin opcode <= bus; ip <= ip + 1; end

            // ALU modrm
            8'b00_xxx_0xx: case (tstate)

                0: begin tstate <= 1; main <= FETCHEA; {idir, isize} <= opcode[1:0]; alumode <= opcode[5:3]; end
                1: begin tstate <= 2;

                    flags <= flags_o;
                    if (alumode < 7) begin main <= SETEA; wb <= result; end

                end
                2: begin main <= PREPARE; sel <= 0; end

            endcase

            // ALU ac, #
            8'b00_xxx_10x: case (tstate)

                0: begin tstate <= opcode[0] ? 1 : 2;

                    op1     <= ax;
                    op2     <= bus;
                    isize   <= opcode[0];
                    alumode <= opcode[5:3];
                    ip      <= ip + 1;

                end
                1: begin tstate <= 2; op2[15:8] <= bus; ip <= ip + 1; end
                2: begin main <= PREPARE;

                    flags <= flags_o;
                    if (alumode < 7) if (isize) ax <= result; else ax[7:0] <= result;

                end

            endcase

        endcase

    end

    // Считывание эффективного адреса и регистров
    FETCHEA: case (estate)

        0: begin

            modrm <= bus;
            ip    <= ip + 1;

            // Операнд 1
            case (idir ? bus[5:3] : bus[2:0])

                0: op1 <= isize ? ax : ax[ 7:0];
                1: op1 <= isize ? cx : cx[ 7:0];
                2: op1 <= isize ? dx : dx[ 7:0];
                3: op1 <= isize ? bx : bx[ 7:0];
                4: op1 <= isize ? sp : ax[15:8];
                5: op1 <= isize ? bp : cx[15:8];
                6: op1 <= isize ? si : dx[15:8];
                7: op1 <= isize ? di : bx[15:8];

            endcase

            // Операнд 2
            case (idir ? bus[2:0] : bus[5:3])

                0: op2 <= isize ? ax : ax[ 7:0];
                1: op2 <= isize ? cx : cx[ 7:0];
                2: op2 <= isize ? dx : dx[ 7:0];
                3: op2 <= isize ? bx : bx[ 7:0];
                4: op2 <= isize ? sp : ax[15:8];
                5: op2 <= isize ? bp : cx[15:8];
                6: op2 <= isize ? si : dx[15:8];
                7: op2 <= isize ? di : bx[15:8];

            endcase

            // Вычисление эффективного адреса
            case (bus[2:0])

                0: ea <= bx + si;
                1: ea <= bx + di;
                2: ea <= bp + si;
                3: ea <= bp + di;
                4: ea <= si;
                5: ea <= di;
                6: ea <= bp;
                7: ea <= bx;

            endcase

            // Выбор SS: по умолчанию, если возможно
            if (!sel_seg && (bus[2:0] == 3'h6 && bus[7:6]) || (bus[2:0] == 3'h2) || (bus[2:0] == 3'h3))
                seg_ea <= seg_ss;

            casex (bus)

                8'b00_xxx_110: begin estate <= 1; ea  <= 0; end // disp16
                8'b00_xxx_xxx: begin estate <= 4; sel <= 1; end // без disp
                8'b01_xxx_xxx: begin estate <= 3; end // disp8
                8'b10_xxx_xxx: begin estate <= 1; end // disp16
                8'b11_xxx_xxx: begin estate <= 0; main <= MAIN; end

            endcase

        end

        // Считывание 16-бит displacement
        1: begin estate <= 2; ip <= ip + 1; ea <= ea + bus; end
        2: begin estate <= 4; ip <= ip + 1; ea[15:8] <= ea[15:8] + bus; sel <= 1; end

        // Считывание 8-бит displacement
        3: begin estate <= 4; ip <= ip + 1; ea <= ea + {{8{bus[7]}}, bus[7:0]}; sel <= 1; end

        // Чтение операнда 8bit из памяти
        4: begin

            if (idir) op2 <= bus; else op1 <= bus;
            if (isize) begin estate <= 5; ea <= ea + 1; end
            else       begin estate <= 0; main <= MAIN; end

        end

        // Чтение операнда 16bit из памяти
        5: begin

            if (idir) op2[15:8] <= bus; else op1[15:8] <= bus;

            ea     <= ea - 1;
            main   <= MAIN;
            estate <= 0;

        end

    endcase

    // Запись обратно в память или регистр
    // idir=1 запись в регистр modrm[5:3], idir=0 запись в память ea
    SETEA: case (estate)

        0: begin

            // Запись результата в регистр
            if (idir || (modrm[7:6] == 2'b11)) begin

                case (idir ? modrm[5:3] : modrm[2:0])

                    0: if (isize) ax <= wb; else ax[ 7:0] <= wb[7:0];
                    1: if (isize) cx <= wb; else cx[ 7:0] <= wb[7:0];
                    2: if (isize) dx <= wb; else dx[ 7:0] <= wb[7:0];
                    3: if (isize) bx <= wb; else bx[ 7:0] <= wb[7:0];
                    4: if (isize) sp <= wb; else ax[15:8] <= wb[7:0];
                    5: if (isize) bp <= wb; else cx[15:8] <= wb[7:0];
                    6: if (isize) si <= wb; else dx[15:8] <= wb[7:0];
                    7: if (isize) di <= wb; else bx[15:8] <= wb[7:0];

                endcase

                main <= MAIN;

            end
            // Запись LO-байта в память
            else begin

                estate <= 1;
                data   <= wb[7:0];
                wreq   <= 1;

            end

        end

        // Запись HI-байта или завершение
        1: begin

            if (isize)
                 begin estate <= 2; data <= wb[15:8]; ea <= ea + 1; end
            else begin estate <= 0; wreq <= 0; main <= MAIN; end

        end

        // Завершение записи
        2: begin estate <= 0; wreq <= 0; main <= MAIN; ea <= ea - 1; end

    endcase

    // PUSH
    // POP

endcase

endmodule
