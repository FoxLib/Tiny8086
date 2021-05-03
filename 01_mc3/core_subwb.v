// ===============================
// Обратная запись в байт ModRM
// или в память (зависит от modrm)
// По завершении записи swi -> 0
// ===============================

sub_wb: case (fn2)

    // Запись в регистр
    0: begin

        // Запись либо в регистр, либо в reg-часть от r/m
        if (modrm[7:6] == 2'b11 || dir) begin

            if (bit16) begin

                if (dir) r[ modrm[5:3] ] <= wb[15:0];
                else     r[ modrm[2:0] ] <= wb[15:0];

            end
            // 8 bit
            else begin

                if (dir) begin

                    if (modrm[5]) r[ modrm[4:3] ][15:8] <= wb[7:0];
                    else          r[ modrm[4:3] ][ 7:0] <= wb[7:0];

                end else begin

                    if (modrm[2]) r[ modrm[1:0] ][15:8] <= wb[7:0];
                    else          r[ modrm[1:0] ][ 7:0] <= wb[7:0];

                end

            end

            sub <= subret;
            swi <= 1'b0;

        end
        // Запись в память байта или слова
        else begin

            wren <= 1'b1;
            out  <= wb[7:0];
            fn2  <= 1;

        end

    end

    // Запись 8 бит
    1: begin

        if (bit16) begin fn2 <= 2; eff <= eff + 1; out <= wb[15:8]; end
        else       begin fn2 <= 0; sub <= subret; wren <= 1'b0; swi <= 1'b0; end

    end

    // Запись 16 бит
    2: begin fn2 <= 0; swi <= 1'b0; sub <= subret; wren <= 1'b0; eff <= eff - 1; end

endcase
