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
            8'h26: begin ip <= ip + 1; sel_seg <= 1; seg_ea <= seg_es; end
            8'h2E: begin ip <= ip + 1; sel_seg <= 1; seg_ea <= seg_cs; end
            8'h36: begin ip <= ip + 1; sel_seg <= 1; seg_ea <= seg_ss; end
            8'h3E: begin ip <= ip + 1; sel_seg <= 1; seg_ea <= seg_ds; end
            8'hF2: begin ip <= ip + 1; sel_rep <= 1; end
            8'hF3: begin ip <= ip + 1; sel_rep <= 2; end
            // Неиспользуемые префиксы
            8'h0F, 8'hF0, 8'h64, 8'h65, 8'h66, 8'h67: begin ip <= ip + 1; end

            // АЛУ modrm
            8'b00_xxx_0xx: case (tstate)

                0: begin tstate <= 1; {isize, idir} <= opcode[1:0]; main <= FETCHEA; alumode <= opcode[5:3]; end

            endcase

        endcase

    end

    // Считывание эффективного адреса и регистров
    FETCHEA: case (estate)

        0: begin

            modrm <= bus;

            // Операнд 1
            case (idir ? bus[2:0] : bus[5:3])

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
            case (idir ? bus[5:3] : bus[2:0])

                0: op2 <= isize ? ax : ax[ 7:0];
                1: op2 <= isize ? cx : cx[ 7:0];
                2: op2 <= isize ? dx : dx[ 7:0];
                3: op2 <= isize ? bx : bx[ 7:0];
                4: op2 <= isize ? sp : ax[15:8];
                5: op2 <= isize ? bp : cx[15:8];
                6: op2 <= isize ? si : dx[15:8];
                7: op2 <= isize ? di : bx[15:8];

            endcase

            // Если выбраны оба регистра, то вернуться обратно
            if (bus[7:6] == 2'b11) main <= MAIN;

            // -- иначе начать считывание из памяти

        end

    endcase

endcase

endmodule
