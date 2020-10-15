module cpu
(
    // Основной контур для процессора
    input   wire        clock,              // 25 mhz
    output  wire [19:0] address,
    input   wire [ 7:0] i_data,             // i_data = ram[address]
    output  reg  [ 7:0] o_data,
    output  reg         we
);

`include "cpu_decl.v"

// Выбор текущего адреса
assign address = bus ? {seg[segment_id], 4'h0} + ea : {seg[SEG_CS], 4'h0} + ip;

// Вычисление условий
wire [7:0] branches = {

    (flags[SF] ^ flags[OF]) | flags[ZF], // 7: (ZF=1) OR (SF!=OF)
    (flags[SF] ^ flags[OF]),             // 6: SF!=OF
     flags[PF], flags[SF],               // 5: PF; 4: SF
     flags[CF] | flags[OF],              // 3: CF != OF
     flags[ZF], flags[CF], flags[OF]     // 2: OF; 1: CF; 0: ZF
};

// Исполнительный блок
always @(posedge clock) begin

    wb <= 0; // Запись в регистр
    wf <= 0; // Запись флагов

    case (fn)

        // Сброс перед запуском инструкции
        // -------------------------------------------------------------
        START: begin

            opcode      <= 0;
            bus         <= 0;       // address = CS:IP
            busen       <= 1;       // Считывать из памяти modrm rm-часть
            segment_id  <= SEG_DS;  // Значение сегмента по умолчанию DS:
            segment_px  <= 1'b0;    // Наличие сегментного префикса
            rep         <= 2'b0;    // Нет префикса REP:
            ea          <= 0;       // Эффективный адрес
            fn          <= LOAD;    // Номер главной фунции
            fnext       <= START;   // Возврат по умолчанию
            we          <= 0;       // Разрешение записи
            i_dir       <= 0;       // Ширина операнда 0=8, 1=16
            i_size      <= 0;       // Направление 0=[rm,r], 1=[r,rm]
            wb_data     <= 0;       // Данные на запись (modrm | reg)
            wb_reg      <= 0;       // Номер регистра на запись
            s1 <= 0; s2 <= 0;
            s3 <= 0; s4 <= 0;

        end

        // Дешифратор опкода
        // -------------------------------------------------------------
        LOAD: begin

            // Параметры по умолчанию
            i_size <= i_data[0];
            i_dir  <= i_data[1];
            opcode <= i_data;

            // Поиск опкода по маске
            casex (i_data)

                8'b00001111: begin fn <= EXTEND; end // Префикс расширения
                8'b001xx110: begin fn <= LOAD; segment_id <= i_data[4:3]; segment_px <= 1; end // Сегментные префиксы
                8'b1110001x: begin fn <= LOAD; rep <= i_data[1:0]; end // REPNZ, REPZ
                // FS, GS, opsize, adsize
                8'b0110010x,
                8'b0110011x, /* begin fn <= UNDEF; end */
                // LOCK:
                8'b11100000: begin fn <= LOAD; end
                // ALU rm | ALU a,imm
                8'b00xxx0xx: begin fn <= MODRM; alu <= i_data[5:3]; end
                8'b00xxx10x: begin fn <= INSTR; alu <= i_data[5:3]; end
                // MOV rm, i | LEA r, m
                8'b1100011x, 8'b10001101: begin fn <= INSTR; busen <= 0; end
                // INC|DEC r
                8'b0100xxxx: begin fn <= INSTR;

                    alu <= i_data[3] ? ALU_SUB : ALU_ADD;
                    op1 <= r16[i_data[2:0]];
                    op2 <= 1;
                    i_size <= 1;

                end
                // XCHG r, a
                8'b10010xxx: begin fn <= INSTR;

                    op1 <= r16[REG_AX];
                    op2 <= r16[i_data[2:0]];
                    i_size <= 1;

                end
                // PUSH r
                8'b01010xxx: begin fn <= PUSH; wb_data <= r16[i_data[2:0]]; end
                // POP r|s
                8'b01011xxx,
                8'b000xx111: begin fn <= POP;  fnext <= INSTR; end
                // PUSH s
                8'b000xx110: begin fn <= PUSH; wb_data <= seg[i_data[4:3]]; end
                // Установка и снятие флагов CLx/STx
                8'b1111100x: begin fn <= START; wf <= 1; wb_flag <= {flags[11:1], i_data[0]}; end // CF
                8'b1111101x: begin fn <= START; wf <= 1; wb_flag <= {flags[11:10], i_data[0], flags[8:0]}; end // IF
                8'b1111110x: begin fn <= START; wf <= 1; wb_flag <= {flags[11], i_data[0], flags[9:0]}; end // IF
                // Grp#1 ALU
                8'b100000xx: begin fn <= MODRM; i_dir <= 0; end
                // TEST rm, r
                8'b1000010x: begin fn <= MODRM; alu <= ALU_AND; end
                // CBW|CWD
                8'b10011000: begin fn <= START; i_size <= 0; wb_reg <= REG_AH; wb <= 1; wb_data <= {8{r16[REG_AX][7]}};   end
                8'b10011001: begin fn <= START; i_size <= 1; wb_reg <= REG_DX; wb <= 1; wb_data <= {16{r16[REG_AX][15]}}; end
                // Переход к исполнению инструкции
                default: begin fn <= INSTR;

                    // Определить наличие байта ModRM для опкода
                    casex (i_data)

                        8'b1000xxxx, 8'b1100000x, 8'b110001xx, 8'b011010x1,
                        8'b110100xx, 8'b11011xxx, 8'b1111x11x, 8'b0110001x: fn <= MODRM;

                    endcase

                end

            endcase

            ip <= ip + 1;

        end

        // Считывание MODRM
        // -------------------------------------------------------------
        MODRM: case (s1)

            // Считывание адреса или регистров
            0: begin

                s1    <= 1;
                modrm <= i_data;
                ip    <= ip + 1;

                // Первый операнд (i_dir=1 будет выбрана reg-часть)
                case (i_dir ? i_data[5:3] : i_data[2:0])

                    3'b000: op1 <= i_size ? r16[REG_AX] : r16[REG_AX][ 7:0];
                    3'b001: op1 <= i_size ? r16[REG_CX] : r16[REG_CX][ 7:0];
                    3'b010: op1 <= i_size ? r16[REG_DX] : r16[REG_DX][ 7:0];
                    3'b011: op1 <= i_size ? r16[REG_BX] : r16[REG_BX][ 7:0];
                    3'b100: op1 <= i_size ? r16[REG_SP] : r16[REG_AX][15:8];
                    3'b101: op1 <= i_size ? r16[REG_BP] : r16[REG_CX][15:8];
                    3'b110: op1 <= i_size ? r16[REG_SI] : r16[REG_DX][15:8];
                    3'b111: op1 <= i_size ? r16[REG_DI] : r16[REG_BX][15:8];

                endcase

                // Второй операнд (i_dir=1 будет выбрана rm-часть)
                case (i_dir ? i_data[2:0] : i_data[5:3])

                    3'b000: op2 <= i_size ? r16[REG_AX] : r16[REG_AX][ 7:0];
                    3'b001: op2 <= i_size ? r16[REG_CX] : r16[REG_CX][ 7:0];
                    3'b010: op2 <= i_size ? r16[REG_DX] : r16[REG_DX][ 7:0];
                    3'b011: op2 <= i_size ? r16[REG_BX] : r16[REG_BX][ 7:0];
                    3'b100: op2 <= i_size ? r16[REG_SP] : r16[REG_AX][15:8];
                    3'b101: op2 <= i_size ? r16[REG_BP] : r16[REG_CX][15:8];
                    3'b110: op2 <= i_size ? r16[REG_SI] : r16[REG_DX][15:8];
                    3'b111: op2 <= i_size ? r16[REG_DI] : r16[REG_BX][15:8];

                endcase

                // Подготовка эффективного адреса
                case (i_data[2:0])

                    3'b000: ea <= r16[REG_BX] + r16[REG_SI];
                    3'b001: ea <= r16[REG_BX] + r16[REG_DI];
                    3'b010: ea <= r16[REG_BP] + r16[REG_SI];
                    3'b011: ea <= r16[REG_BP] + r16[REG_DI];
                    3'b100: ea <= r16[REG_SI];
                    3'b101: ea <= r16[REG_DI];
                    3'b110: ea <= i_data[7:6] == 2'b00 ? 0 : r16[REG_BP]; // disp16 | bp
                    3'b111: ea <= r16[REG_BX];

                endcase

                // Выбор сегмента SS: для BP
                if (!segment_px)
                casex (i_data)
                    8'bxx_xxx_01x, // [bp+si|di]
                    8'b01_xxx_110, // [bp+d8|d16]
                    8'b10_xxx_110: segment_id <= SEG_SS;
                endcase

                // Переход сразу к исполнению инструкции: операнды уже получены
                casex (i_data)

                    8'b00_xxx_110: begin s1 <= 2; end // +disp16
                    8'b00_xxx_xxx: begin s1 <= 4; bus <= busen; if (!busen) fn <= INSTR; end // Читать операнд из памяти
                    8'b01_xxx_xxx: begin s1 <= 1; end // +disp8
                    8'b10_xxx_xxx: begin s1 <= 2; end // +disp16
                    8'b11_xxx_xxx: begin fn <= INSTR; end // Перейти к исполению

                endcase

            end

            // Чтение 8 битного signed disp
            1: begin s1 <= 4; ip <= ip + 1; ea <= ea + {{8{i_data[7]}}, i_data}; bus <= busen; if (!busen) fn <= INSTR; end

            // Чтение 16 битного unsigned disp16
            2: begin s1 <= 3; ip <= ip + 1; ea <= ea + i_data; end
            3: begin s1 <= 4; ip <= ip + 1; ea[15:8] <= ea[15:8] + i_data; bus <= busen; if (!busen) fn <= INSTR; end

            // Чтение операнда из памяти 8 bit
            4: begin

                if (i_dir) op2 <= i_data; else op1 <= i_data;
                if (i_size) begin s1 <= 5; ea <= ea + 1; end else fn <= INSTR;

            end

            // Операнд 16 bit
            5: begin

                if (i_dir) op2[15:8] <= i_data; else op1[15:8] <= i_data;

                ea <= ea - 1;
                fn <= INSTR;

            end

        endcase

        // Исполнение инструкции
        // -------------------------------------------------------------
        INSTR: casex (opcode)

            // <alu> rm
            8'b00xxx0xx: begin

                wb_data <= alu_r;
                wb_flag <= alu_f;
                wf <= 1;
                fn <= (alu != ALU_CMP) ? WBACK : START;

            end

            // <alu> a, imm
            8'b00xxx10x: case (s3)

                // Инициализация
                0: begin

                    op1 <= i_size ? r16[REG_AX] : r16[REG_AX][7:0];
                    op2 <= i_data;
                    s3  <= i_size ? 1 : 2;
                    ip  <= ip + 1;

                end

                // Считывание старшего байта
                1: begin s3 <= 2; op2[15:8] <= i_data; ip <= ip + 1; end

                // Запись в регистр и выход из процедуры
                2: begin

                    fn      <= START;
                    wb_flag <= alu_f;
                    wb_data <= alu_r;
                    wb_reg  <= REG_AX;
                    wb      <= (alu != ALU_CMP);
                    wf      <= 1;

                end

            endcase

            // MOV r, i
            8'b1011xxxx: case (s3)

                // 8 bit
                0: begin

                    wb_data <= i_data;
                    wb_reg  <= opcode[2:0];
                    wb      <= ~opcode[3];
                    i_size  <= opcode[3];
                    fn      <= opcode[3] ? fn : START;
                    s3      <= 1;
                    ip      <= ip + 1;

                end

                // 16 bit
                1: begin

                    wb_data[15:8] <= i_data;
                    wb <= 1;
                    fn <= START;
                    ip <= ip + 1;

                end

            endcase

            // MOV rm
            8'b100010xx: begin wb_data <= op2; fn <= WBACK; end

            // MOV rm, i
            8'b1100011x: case (s3)

                // 8 bit
                0: begin

                    wb_data <= i_data;
                    ip      <= ip + 1;
                    i_dir   <= 0;
                    s3      <= 1;

                    if (i_size == 0) begin fn <= WBACK; bus <= 1; end

                end

                // 16 bit
                1: begin wb_data[15:8] <= i_data; ip <= ip + 1; bus <= 1; fn <= WBACK; end

            endcase

            // LEA r16, m
            8'b10001101: begin wb_data <= ea; wb_reg <= modrm[5:3]; wb <= 1; fn <= START; end

            // Jccc
            8'b0111xxxx: begin

                if (branches[ opcode[3:1] ] ^ opcode[0])
                    ip <= ip + 1 + {{8{i_data[7]}}, i_data[7:0]};
                else
                    ip <= ip + 1;

                fn <= START;

            end

            // INC | DEC r16
            8'b0100xxxx: begin

                wb_data <= alu_r;
                wb_flag <= {alu_f[11:1], flags[CF]};
                wb_reg  <= opcode[2:0];
                wb <= 1;
                wf <= 1;
                fn <= START;

            end

            // XCHG ax, r16
            8'b10010xxx: case (s3)

                0: begin s3 <= 1;     wb_data <= op2; wb <= 1; wb_reg <= REG_AX; end
                1: begin fn <= START; wb_data <= op1; wb <= 1; wb_reg <= opcode[2:0]; end

            endcase

            // POP r|s
            8'b01011xxx: begin fn <= START; wb_reg <= opcode[2:0]; wb <= 1; end
            8'b000xx111: begin fn <= START; seg[opcode[4:3]] <= wb_data; end

            // <alu> imm
            8'b100000xx: case (s3)

                // Считывание imm и номера кода операции
                0: begin s3 <= 1; alu <= modrm[5:3]; busen <= bus; bus <= 0; end
                1: begin s3 <= 2; op2 <= i_data; ip <= ip + 1; end
                2: begin s3 <= 3;

                    case (opcode[1:0])
                        2'b01: begin op2[15:8] <= i_data; ip <= ip + 1; end // imm16
                        2'b11: begin op2[15:8] <= {8{op2[7]}}; end // sign8
                    endcase

                end
                // Запись
                3: begin

                    bus     <= busen;
                    wb_data <= alu_r;
                    wb_flag <= alu_f;
                    wf  <= 1;
                    fn  <= (alu != ALU_CMP) ? WBACK : START;

                end

            endcase

            // MOV a,[m] | [m],a
            8'b101000xx: case (s3)

                // Прочесть адрес
                0: begin ea[7:0]  <= i_data; ip <= ip + 1; s3 <= 1; wb_reg <= REG_AX; end
                1: begin ea[15:8] <= i_data; ip <= ip + 1; bus <= 1; s3 <= i_dir ? 2 : 5; end

                // Запись A
                2: begin s3 <= 3; we <= 1;      o_data <= r16[REG_AX][ 7:0]; end
                3: begin s3 <= 4; we <= i_size; o_data <= r16[REG_AX][15:8]; ea <= ea + 1; end
                4: begin fn <= START; we <= 0; end

                // Чтение A
                5: begin s3 <= 6;     wb <= ~i_size; wb_data <= i_data; ea <= ea + 1; end
                6: begin fn <= START; wb <=  i_size; wb_data[15:8] <= i_data; end

            endcase

            // TEST rm,r
            8'b1000010x: begin wb_flag <= alu_f; wf <= 1; fn <= START; end

        endcase

        // Расширенные инструции
        // -------------------------------------------------------------
        EXTEND: begin
        end

        // Прерывание
        // -------------------------------------------------------------
        INTR: begin
        end

        // Сохранение данных [wb_data, i_size, i_dir, modrm]
        // -------------------------------------------------------------
        WBACK: case (s2)

            // Выбор - регистр или память
            0: begin

                // reg-часть или rm:reg
                if (i_dir || modrm[7:6] == 2'b11) begin

                    wb_reg  <= i_dir ? modrm[5:3] : modrm[2:0];
                    wb      <= 1;
                    bus     <= 0;
                    fn      <= fnext;

                end
                // Если modrm указывает на память, записать первые 8 бит
                else begin o_data <= wb_data[7:0]; we <= 1; s2 <= 1; end

            end

            // Запись 16 бит?
            1: if (i_size) begin

                ea     <= ea + 1;
                o_data <= wb_data[15:8];
                s2     <= 2;

            end
            // Завершение записи 8 бит
            else begin we <= 0; bus <= 0; fn <= fnext; end

            // Запись 16 бит закончена
            2: begin   we <= 0; bus <= 0; fn <= fnext; end

        endcase

        // Запись в стек <- wb_data | bus,wb,wb_reg,segment_id,ea,i_size
        // -------------------------------------------------------------
        PUSH: case (s4)

            0: begin s4 <= 1;

                segment_id <= SEG_SS;
                ea      <= r16[REG_SP] - 2;
                bus     <= 1;
                o_data  <= wb_data[7:0];
                we      <= 1;

            end
            1: begin s4 <= 2;

                o_data  <= wb_data[15:8];
                wb      <= 1;
                wb_reg  <= REG_SP;
                wb_data <= r16[REG_SP] - 2;
                i_size  <= 1;
                ea      <= ea + 1;

            end
            2: begin we <= 0; bus <= 0; fn <= fnext; s4 <= 0; end

        endcase

        // Чтение из стека -> wb_data | bus,wb,wb_reg,segment_id,ea,i_size
        // -------------------------------------------------------------
        POP: case (s4)

            0: begin s4 <= 1;

                segment_id <= SEG_SS;
                ea      <= r16[REG_SP];
                bus     <= 1;
                wb      <= 1;
                wb_reg  <= REG_SP;
                wb_data <= r16[REG_SP] + 2;
                i_size  <= 1;

            end

            1: begin s4 <= 2; wb_data[ 7:0] <= i_data; ea <= ea + 1; end
            2: begin s4 <= 0; wb_data[15:8] <= i_data; bus <= 0; fn <= fnext; end

        endcase

    endcase

end

// wb=запись wb_data резрешена в регистр wb_reg
// [wb, wb_data, wb_reg, i_size]
always @(negedge clock) begin

    if (wb) begin

        if (i_size) r16[ wb_reg ] <= wb_data; // 16 bit
        else if (wb_reg[2])
             r16[ wb_reg[1:0] ][15:8] <= wb_data[7:0]; // HI8
        else r16[ wb_reg[1:0] ][ 7:0] <= wb_data[7:0]; // LO8

    end

    if (wf) flags <= wb_flag;

end

// ---------------------------------------------------------------------
// Арифметико-логическое устройство
// ---------------------------------------------------------------------

reg  [11:0] alu_f; // Результирующие флаги
reg  [16:0] alu_r; // Результат выполнения op1 <alu> op2
wire [ 3:0] alu_top = i_size ? 15 : 7;

always @* begin

    alu_f = flags;

    // Вычисление результата
    case (alu)

        ALU_ADD: alu_r = op1 + op2;
        ALU_ADC: alu_r = op1 + op2 + flags[CF];
        ALU_SBB: alu_r = op1 - op2 - flags[CF];
        ALU_SUB,
        ALU_CMP: alu_r = op1 - op2;
        ALU_XOR: alu_r = op1 ^ op2;
        ALU_OR:  alu_r = op1 | op2;
        ALU_AND: alu_r = op1 & op2;

    endcase

    // Общая схема переносов
    alu_f[CF] = alu_r[ alu_top + 1 ];
    alu_f[AF] = op1[4] ^ op2[4] ^ alu_r[4];

    // Вычисление флага OF
    case (alu)

        ALU_ADD,
        ALU_ADC: alu_f[OF] = (op1[alu_top] ^ op2[alu_top] ^ 1) & (op1[alu_top] ^ alu_r[alu_top]);
        ALU_SUB,
        ALU_SBB,
        ALU_CMP: alu_f[OF] = (op1[alu_top] ^ op2[alu_top] ^ 0) & (op1[alu_top] ^ alu_r[alu_top]);
        // Логические сбрасывают OF, CF, AF
        default: begin alu_f[OF] = 0; alu_f[CF] = 0; alu_f[AF] = alu_r[4]; end

    endcase

    // SZP устанавливаются для всех одинаково
    alu_f[SF] = alu_r[alu_top];
    alu_f[ZF] = (i_size ? alu_r[15:0] : alu_r[7:0]) == 0;
    alu_f[PF] = ~^alu_r[7:0];

end

endmodule

