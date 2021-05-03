
// ---------------------------------------------------------------------
// Считывание префиксов и опкода
// ---------------------------------------------------------------------

sub_fetch: begin

    ip   <= ip + 1;
    wren <= 1'b0;

    casex (data)

        // Загрузка сегмента эффективного адреса
        8'b001x_x110: begin _override <= 1'b1; _seg <= s[ data[4:3] ]; end
        8'b0000_1111: begin  sub <= sub_extended; end
        8'b1111_0000: begin /* lock: */ end
        8'b1111_001x: begin _rep <= data[1:0]; end

        // Другие префиксы опускаются, потому что мне лень реализовывать их
        default: begin

            // Защелкивание кода инструкции и префикса
             rep   <= _rep;   override <= _override;  seg <= _seg;
            _rep   <= 2'b00; _override <= 1'b0;      _seg <= s[seg_ds];
            fn     <= 1'b0;
            fn2    <= 1'b0;
            bit16  <= 1'b0;
            dir    <= 1'b0;
            opcode <= data;

            // Декодирование опкода
            casex (data)

                // Инструкции ADD|ADC|SUB|SBB|AND|XOR|OR|CMP <modrm>|Acc,i8/16
                8'b00_xxx_0xx: begin sub <= sub_modrm; alu <= data53; bit16 <= data[0]; dir <= data[1]; end
                8'b00_xxx_10x: begin sub <= sub_exec;  alu <= data53; bit16 <= data[0]; end

                // INC|DEC r16
                8'b0100_xxxx: begin sub <= sub_exec;  alu <= data[3] ? alu_sub : alu_add; bit16 <= 1'b1;
                                    op1 <= r[data20]; op2 <= 1'b1; end

                8'b000x_x110, // PUSH r16
                8'b1001_1100, // PUSHF
                8'b0101_0xxx: // PUSH sreg
                begin

                    sub <= sub_exec;  wren <= 1'b1;
                    seg <= s[seg_ss]; eff  <= r[reg_sp] - 2;
                    swi <= 1'b1;

                    casex (data)

                        8'b0101_0xxx: out <= r[data20][7:0];
                        8'b000x_x110: out <= s[data[4:3]][7:0];
                        8'b0101_0xxx: out <= flags[7:0];

                    endcase

                end

                8'b000x_x111, // POP r16
                8'b0101_1xxx, // POP sreg
                8'b1001_1101: // POPF
                begin

                    sub <= sub_exec;  r[reg_sp] <= r[reg_sp] + 2;
                    seg <= s[seg_ss]; eff <= r[reg_sp];
                    swi <= 1'b1;

                end

                // Групповые арифметические
                8'b1000_00xx: begin sub <= sub_modrm; bit16 <= data[0]; dir <= 1'b0; end

                // TEST rm,r
                // XCHG rm,r
                8'b1000_01xx: begin sub <= sub_modrm; bit16 <= data[0]; dir <= 1'b0; alu <= alu_and; end

                // MOV rm,r | r,rm
                8'b1000_10xx: begin sub <= sub_modrm; bit16 <= data[0]; dir <= data[1]; end

                // XCHG AX, r16
                8'b1001_0xxx: begin r[reg_ax] <= r[data20]; r[data20] <= r[reg_ax]; end

                // J<cond> +d8
                8'b0111_xxxx: if (condition[data[3:1]] ^ data[0]) sub <= sub_exec; else ip <= ip + 2;

                // HLT, CMC
                8'b1111_0100: ip <= ip;
                8'b1111_0101: flags[flag_c] <= ~flags[flag_c];

                // CLC, STC, CLI, STI, CLD, STD
                8'b1111_100x: flags[flag_c] <= data[0];
                8'b1111_101x: flags[flag_i] <= data[0];
                8'b1111_110x: flags[flag_d] <= data[0];

                // CBW, CWD
                8'b1001_1000: r[reg_ax] <= {{8{r[reg_ax][7]}}, r[reg_ax][7:0]};
                8'b1001_1001: r[reg_dx] <= {16{r[reg_ax][15]}};

                // LAHF, SAHF
                8'b1001_1110: flags <= r[reg_ax][15:8];
                8'b1001_1111: r[reg_ax][15:8] <= flags[7:0];

                // Все остальные инструкции, не требующие первого такта
                default: sub <= sub_exec;

            endcase

        end

    endcase

end
