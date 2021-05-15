module portctl
(
    input   wire        clock,      // cpu host clock

    // Управление
    input   wire        port_clk,
    input   wire [15:0] port,
    output  reg  [ 7:0] port_i,     // К процессору
    input   wire [ 7:0] port_o,     // От процессора
    input   wire        port_w,

    // Устройства
    output  reg  [10:0] vga_cursor
);

initial begin vga_cursor = 0; port_i = 0; end

reg [ 7:0] cga_reg;

/*
 * Обработка ввода-вывода
 */

always @(posedge clock) begin

    if (port_clk) begin

        if (port_w)
        case (port)

            // Выбор регистра CGA/EGA
            16'h3D4: cga_reg <= port_o;

            // Запись в регистр
            16'h3D5: case (cga_reg)

                // Положение курсора на экране
                8'h0E: vga_cursor[10:8] <= port_o[2:0];
                8'h0F: vga_cursor[ 7:0] <= port_o;

            endcase

        endcase
        else case (port)

            16'h3D4: port_i <= cga_reg;
            16'h3D5: case (cga_reg)

                8'h0E: port_i <= vga_cursor[10:8];
                8'h0F: port_i <= vga_cursor[ 7:0];

            endcase

        endcase

    end

end

endmodule
