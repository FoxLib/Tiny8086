module cpu
(
    // Основной контур для процессора
    input   wire        clock,              // 25 mhz
    output  wire [19:0] address,
    input   wire [ 7:0] i_data,             // i_data = ram[address]
    output  reg  [ 7:0] o_data,
    output  reg         we,

    // Порты ввода-вывода
    output  reg  [15:0] port_address,
    output  reg         port_write,
    output  reg         port_read,
    input   wire [ 7:0] port_in,
    output  reg  [ 7:0] port_out,
    input   wire        port_ready,

    // PIC: Программируемый контроллер прерываний
    input   wire        irq_signal,         // Счетчик IRQ (0 или 1)
    input   wire [ 7:0] irq                 // Номер IRQ (0..255)
);

`include "cpu_decl.v"

// Выбор текущего адреса, segment_id[2] = 1 означает прерывание
assign address = bus ? {(segment_id[2] ? 16'h0000 : seg[segment_id]), 4'h0} + ea : {seg[SEG_CS], 4'h0} + ip;

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
    port_read  <= 0; // Строб чтения из порта
    port_write <= 0; // Строб записи в порт

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
            fnext       <= START;   // Возврат по умолчанию
            rep_ft      <= 0;       // =0 REP, =1 REPZ|NZ
            we          <= 0;       // Разрешение записи
            i_dir       <= 0;       // Ширина операнда 0=8, 1=16
            i_size      <= 0;       // Направление 0=[rm,r], 1=[r,rm]
            wb_data     <= 0;       // Данные на запись (modrm | reg)
            wb_reg      <= 0;       // Номер регистра на запись
            ip_start    <= ip;      // Для REP:
            s1 <= 0; s2 <= 0;
            s3 <= 0; s4 <= 0;

            // IRQ прерывание вызывается, если счетчик изменился (irq_accept != irq_signal) и IF=1
            if ((irq_accept ^ irq_signal) && flags[IF]) begin

                fn          <= INTR;
                wb_data     <= irq;
                irq_accept  <= irq_signal;

            end
            // TF=1 (Trace Flag включен) и IF=1
            else if (flags[IF] && flags[TF] && trace_ff) begin

                wb_data  <= 1;
                fn       <= INTR;

            end
            // Выбор номера главной фунции
            else fn <= halt ? START : LOAD;

            // FlipFlop: сначала выполнится инструкция, потом вызовается INT 1>
            if (flags[IF] && flags[TF]) trace_ff <= ~trace_ff;

        end

        // Дешифратор опкода
        // -------------------------------------------------------------
        LOAD: begin

            // Параметры по умолчанию
            i_size <= i_data[0];
            i_dir  <= i_data[1];
            opcode <= i_data;
            ip     <= ip + 1;

            // Поиск опкода по маске
            casex (i_data)

                8'b00001111: begin fn <= EXTEND; end // Префикс расширения
                8'b001xx110: begin fn <= LOAD; segment_id <= i_data[4:3]; segment_px <= 1; end // Сегментные префиксы
                8'b1111001x: begin fn <= LOAD; rep <= i_data[1:0]; end // REPNZ, REPZ
                // FS, GS, opsize, adsize
                8'b0110010x,
                8'b0110011x, /* begin fn <= UNDEF; end */
                // LOCK: FWAIT
                8'b10011011,
                8'b11110000: begin fn <= LOAD; end
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
                8'b01010xxx: begin fn <= PUSH; // PUSH r
                    wb_data <= r16[i_data[2:0]];
                end
                // POP xxx
                8'b01011xxx, // POP r
                8'b000xx111, // POP s
                8'b10011101, // POPF
                8'b1100101x, // RETF [i]
                8'b1x001111, // POP rm | IRET
                8'b1100001x: begin fn <= POP; fnext <= INSTR; end // RET [i]
                // PUSH s
                8'b000xx110: begin fn <= PUSH; wb_data <= seg[i_data[4:3]]; end
                // PUSHF
                8'b10011100: begin fn <= PUSH; wb_data <= flags; end
                // Установка и снятие флагов CLx/STx, простые инструкции
                8'b1111100x: begin fn <= START; wf <= 1; wb_flag <= {flags[11:1], i_data[0]}; end // CF
                8'b1111101x: begin fn <= START; wf <= 1; wb_flag <= {flags[11:10], i_data[0], flags[8:0]}; end // IF
                8'b1111110x: begin fn <= START; wf <= 1; wb_flag <= {flags[11], i_data[0], flags[9:0]}; end // IF
                8'b10011110: begin fn <= START; wb_flag <= r16[REG_AX][15:8]; wf <= 1; end // SAHF
                8'b10011111: begin fn <= START; wb_data <= {flags[7:2],1'b1,flags[0]}; wb_reg <= REG_AH; i_size <= 0; wb <= 1; end // LAHF
                8'b11010110: begin fn <= START; wb_data <= {8{flags[0]}}; wb_reg <= REG_AL; i_size <= 0; wb <= 1; end // SALC
                8'b11110100: begin fn <= START; halt <= 1; end // HALT
                8'b11110101: begin fn <= START; wb_flag <= {flags[7:1], ~flags[0]}; wf <= 1; end // CMC
                8'b100000xx, // Grp#1 ALU
                8'b1000011x: begin fn <= MODRM; // XCHG rm, r
                    i_dir <= 0;
                end
                8'b1000010x: begin fn <= MODRM; // TEST rm | TEST a,i
                    alu <= ALU_AND;
                end
                8'b10011000: begin fn <= START; // CBW
                    i_size  <= 0;
                    wb_reg  <= REG_AH;
                    wb      <= 1;
                    wb_data <= {8{r16[REG_AX][7]}};
                end
                8'b10011001: begin fn <= START; // CWD
                    i_size  <= 1;
                    wb_reg  <= REG_DX;
                    wb      <= 1;
                    wb_data <= {16{r16[REG_AX][15]}};
                end
                // LOOP|NZ|Z
                8'b1110000x,
                8'b11100010: begin fn <= INSTR; i_size <= 1; wb_reg <= REG_CX; wb_data <= r16[REG_CX] - 1; wb <= 1; end
                // MOV s,rm
                8'b10001110: begin fn <= MODRM; i_size <= 1; end
                // XLATB
                8'b11010111: begin fn <= INSTR; ea <= r16[REG_BX] + r16[REG_AX][7:0]; bus <= 1; end
                // LES|LDS r,m
                8'b1100010x: begin fn <= MODRM; i_size <= 1; i_dir <= 1; end
                // INT 1,3,4
                8'b11001100: begin fn <= INTR; intr <= 3; end // INT 3
                8'b11001110: begin fn <= flags[OF] ? INTR : START; intr <= 4; end // INTO
                8'b11110001: begin fn <= INTR; intr <= 1; end // INT 1
                8'b1111x11x, // Grp#4|5
                8'b1100000x, // Сдвиги
                8'b110100xx: begin fn <= MODRM; i_dir <= 0; end
                // Переход к исполнению инструкции
                default: begin fn <= INSTR;

                    // Определить наличие байта ModRM для опкода
                    casex (i_data)

                        8'b1000xxxx, 8'b1100000x, 8'b110001xx, 8'b011010x1,
                        8'b110100xx, 8'b11011xxx, 8'b1111x11x, 8'b0110001x: fn <= MODRM;

                    endcase

                end

            endcase

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
            1: begin s1 <= 4; ip <= ip + 1; ea <= ea + signex; bus <= busen; if (!busen) fn <= INSTR; end

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

            8'b00xxx0xx: begin              // <alu> rm

                wb_data <= alu_r;
                wb_flag <= alu_f;
                wf <= 1;
                fn <= (alu != ALU_CMP) ? WBACK : START;

            end
            8'b00xxx10x: case (s3)          // <alu> a, imm

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
            8'b1011xxxx: case (s3)          // MOV r, i

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
            8'b100010xx: begin              // MOV rm

                wb_data <= op2;
                fn      <= WBACK;

            end
            8'b1100011x: case (s3)          // MOV rm, i

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
            8'b10001101: begin              // LEA r16, m

                wb_data <= ea;
                wb_reg  <= modrm[5:3];
                wb      <= 1;
                fn      <= START;

            end
            8'b0111xxxx: begin              // Jccc

                // Проверка на выполнение условия в branches
                if (branches[ opcode[3:1] ] ^ opcode[0])
                    ip <= ip + 1 + signex;
                else
                    ip <= ip + 1;

                fn <= START;

            end
            8'b0100xxxx: begin              // INC | DEC r16

                wb_data <= alu_r;
                wb_flag <= {alu_f[11:1], flags[CF]};
                wb_reg  <= opcode[2:0];
                wb <= 1;
                wf <= 1;
                fn <= START;

            end
            8'b10010xxx: case (s3)          // XCHG ax, r16

                0: begin s3 <= 1;     wb_data <= op2; wb <= 1; wb_reg <= REG_AX; end
                1: begin fn <= START; wb_data <= op1; wb <= 1; wb_reg <= opcode[2:0]; end

            endcase
            8'b01011xxx: begin fn <= START; // POP r
                wb_reg <= opcode[2:0]; wb <= 1;
            end
            8'b000xx111: begin fn <= START; // POP s
                seg[opcode[4:3]] <= wb_data;
            end
            8'b100000xx: case (s3)          // <alu> imm

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
            8'b101000xx: case (s3)          // MOV a,[m] | [m],a

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
            8'b1000010x: begin              // TEST rm,r
                wb_flag <= alu_f; wf <= 1; fn <= START;
            end
            8'b100001xx: case (s3)          // XCHG rm,r

                0: begin s3 <= 1;     wb_data <= op1; wb_reg <= modrm[5:3]; wb <= 1; end
                1: begin fn <= WBACK; wb_data <= op2; end

            endcase
            8'b10011101: begin fn <= START; // POPF
                wb_flag <= {wb_data[11:2],1'b1,wb_data[0]}; wf <= 1;
            end
            8'b1010100x: case (s3)          // TEST a,i

                // Считывание младшего байта
                0: begin s3 <= i_size ? 1 : 2; alu <= ALU_AND; op1 <= r16[REG_AX]; op2 <= i_data; ip <= ip + 1; end

                // Если i_size, считывание старшего байта
                1: begin s3 <= 2; op2[15:8] <= i_data; ip <= ip + 1; end

                // Запись результата в АЛУ
                2: begin wf <= 1; wb_flag <= alu_f; fn <= START; end

            endcase
            8'b11101011: begin fn <= START; // JMP b8
                ip <= ip + 1 + signex;
            end
            8'b11101001: case (s3)          // JMP b16
                0: begin s3 <= 1; ea <= i_data; ip <= ip + 1; end
                1: begin fn <= START; ip <= ip + 1 + {i_data, ea[7:0]}; end
            endcase
            8'b11101010: case (s3)          // JMP far

                // Прочитаьть 4 байта для нового CS:IP
                0: begin ip <= ip + 1; s3 <= 1; ea <= i_data; end
                1: begin ip <= ip + 1; s3 <= 2; ea[15:8] <= i_data; end
                2: begin ip <= ip + 1; s3 <= 3; op1 <= i_data; end
                3: begin ip <= ea; seg[SEG_CS] <= {i_data, op1[7:0]}; fn <= START; end

            endcase
            8'b111000xx: begin fn <= START; // LOOP[NZ|Z], JCXZ

                // JCXZ
                if (opcode[1:0] == 2'b11)
                    ip <= ip + 1 + (r16[REG_CX] == 0 ? signex : 0);
                // LOOP, LOOPNZ, LOOPZ
                // Если бит 1 равен 1, то ZF=bit[0] не имеет значения
                else if (r16[REG_CX] && (opcode[1] || flags[ZF] == opcode[0]))
                    ip <= ip + 1 + signex;
                else
                    ip <= ip + 1;

            end
            8'b11101000: case (s3)          // CALL b16

                0: begin s3 <= 1; ea <= i_data; ip <= ip + 1; end
                1: begin fn <= PUSH; wb_data <= ip + 1; ip <= ip + 1 + {i_data, ea[7:0]}; end

            endcase
            8'b11000011: begin fn <= START; // RET
                ip <= wb_data;
            end
            8'b11000010: case (s3)          // RET i16

                // Младший байт
                0: begin s3 <= 1; ea <= i_data; ip <= ip + 1; end

                // Старший байт
                1: begin fn <= START;

                    i_size  <= 1;
                    ip      <= wb_data;
                    wb_data <= r16[REG_SP] + {i_data, ea[7:0]};
                    wb_reg  <= REG_SP;
                    wb      <= 1;

                 end

            endcase
            8'b11001011: case (s3)          // RETF

                0: begin s3 <= 1; op1 <= wb_data; fn <= POP; end
                1: begin s3 <= 2; seg[SEG_CS] <= wb_data; ip <= op1; fn <= START; end

            endcase
            8'b11001010: case (s3)          // RETF i16

                // Младший байт
                0: begin s3 <= 1;

                    fn  <= POP;
                    op1 <= wb_data;
                    op2 <= i_data;
                    ip  <= ip + 1;

                end

                // Старший байт
                1: begin fn <= START;

                    i_size  <= 1;
                    wb_data <= r16[REG_SP] + {i_data, op2[7:0]};
                    wb_reg  <= REG_SP;
                    wb      <= 1;

                    // Установка нового CS:IP из стека
                    seg[SEG_CS] <= wb_data; ip <= op1;

                end

            endcase
            8'b11001111: case (s3)          // IRET

                0: begin s3 <= 1; fn <= POP; ip <= wb_data; end
                1: begin s3 <= 2; fn <= POP; seg[SEG_CS] <= wb_data; end
                2: begin fn <= START; wb_flag <= {wb_data[11:2], 1'b1, wb_data[0]}; wf <= 1; end

            endcase
            8'b10001100: begin fn <= WBACK; // MOV rm,s
                wb_data <= seg[modrm[4:3]];
                i_size  <= 1;
            end
            8'b10001110: begin fn <= START; // MOV s,rm
                seg[modrm[4:3]] <= op2;
            end
            8'b10011010: case (s3)          // CALLF b16

                0: begin ip <= ip + 1; op1[ 7:0] <= i_data; s3 <= 1; end
                1: begin ip <= ip + 1; op1[15:8] <= i_data; s3 <= 2; end
                2: begin ip <= ip + 1; op2[ 7:0] <= i_data; s3 <= 3; end
                3: begin ip <= ip + 1; op2[15:8] <= i_data; s3 <= 4;
                         fn <= PUSH; wb_data <= seg[SEG_CS]; fnext <= INSTR; end
                4: begin fn <= PUSH; wb_data <= ip; s3 <= 5; fnext <= INSTR; end
                5: begin ip <= op1; seg[SEG_CS] <= op2; fn <= START; end

            endcase
            8'b1100010x: case (s3)          // LES|LDS r,m

                0: begin s3 <= 1; wb_data <= op2; wb <= 1; ea <= ea + 2; wb_reg <= modrm[5:3];  end
                1: begin s3 <= 2; wb_data[7:0] <= i_data;  ea <= ea + 1; end
                2: begin seg[ opcode[0] ? SEG_DS : SEG_ES ] <= {i_data, wb_data[7:0]}; fn <= START; end

            endcase
            8'b10001111: case (s3)          // POP rm

                0: begin s3 <= 1; busen <= 0; fn <= MODRM; i_dir <= 0; end
                1: begin bus <= 1; fn <= WBACK; fnext <= START; end

            endcase
            8'b011010x0: case (s3)          // PUSH i

                0: begin s3 <= opcode[1] ? 2 : 1; wb_data <= signex; ip <= ip + 1; end
                1: begin s3 <= 2; wb_data[15:8] <= i_data; ip <= ip + 1; end
                2: begin fn <= PUSH; fnext <= START; end

            endcase
            8'b11010111: begin fn <= START; // XLATB
                wb_reg  <= REG_AX;
                wb_data <= i_data;
                i_size  <= 0;
                wb      <= 1;
            end
            8'b11001101: begin fn <= INTR;  // INT i
                intr <= i_data;
                ip   <= ip + 1;
            end
            8'b1100000x,
            8'b110100xx: case (s3)          // Grp#2 Сдвиги

                // Выбор второго операнда
                0: begin s3 <= 1;

                    alu <= modrm[5:3];

                    if (opcode[4]) op2 <= (opcode[1] ? r16[REG_CX][3:0] : 1);
                    else begin op2 <= i_data[3:0]; ip <= ip + 1; end

                end

                // Процедура сдвига на 0..15 шагов
                1: begin

                    if (op2) begin

                        op1 <= rot_r;
                        wf  <= 1;
                        wb_flag <= rot_f;

                    end
                    // Запись результата
                    else begin wb_data <= op1; fn <= WBACK; end

                    op2 <= op2 - 1;

                end

            endcase
            8'b1110x10x: case (s3)          // IN a,p

                // Чтение номера порта
                0: begin s3 <= 1;

                    port_address <= opcode[3] ? r16[REG_DX] : i_data;
                    if (opcode[3] == 0) ip <= ip + 1;
                    busen <= 0;

                end

                // Чтение, ожидание результата 1 такт
                1: begin s3 <= 2; port_read <= 1; end
                2: begin s3 <= 3; end

                // Запись ответа в AL|AH
                3: begin

                    if (i_size) begin s3 <= 1; busen <= 1; end
                    else fn <= START;

                    i_size  <= 0;
                    wb_reg  <= busen ? REG_AH : REG_AL;
                    wb_data <= port_in;
                    wb      <= 1;

                end

            endcase
            8'b1110x11x: case (s3)          // OUT p,a

                0: begin s3 <= 1;

                    port_address <= opcode[3] ? r16[REG_DX] : i_data;
                    if (opcode[3] == 0) ip <= ip + 1;

                    port_out    <= r16[REG_AX][7:0];
                    port_write  <= 1;

                    if (i_size == 0) fn <= START;

                end
                1: begin

                    port_out    <= r16[REG_AX][15:8];
                    port_write  <= 1;
                    fn <= START;

                end

            endcase
            8'b1111011x: case (modrm[5:3])  // Grp#3

                // TEST imm8/16
                0, 1: case (s3)

                    0: begin s3 <= 1; bus <= 0; alu <= ALU_AND; end
                    1: begin s3 <= i_size ? 2 : 3; op2 <= i_data; ip <= ip + 1; end
                    2: begin s3 <= 3; op2[15:8] <= i_data; ip <= ip + 1; end
                    3: begin wf <= 1; wb_flag <= alu_f; fn <= START; end

                endcase

                // NOT rm
                2: begin wb_data <= ~op1; fn <= WBACK; end

                // NEG rm
                3: case (s3)

                    0: begin s3 <= 1; alu <= ALU_SUB; op2 <= op1; op1 <= 0; end
                    1: begin fn <= WBACK; wb_data <= alu_r; wb_flag <= alu_f; wf <= 1; end

                endcase

            endcase
            8'b1111111x: case (modrm[5:3])  // Grp#4|5

                // INC|DEC rm
                0, 1: case (s3)

                    0: begin s3 <= 1; op2 <= 1; alu <= modrm[3] ? ALU_SUB : ALU_ADD; end
                    1: begin fn <= WBACK; wb_data <= alu_r; wf <= 1; wb_flag <= alu_f; end

                endcase

                // CALL rm
                2: begin ip <= op1; wb_data <= ip; fn <= i_size ? PUSH : UNDEF; end

                // CALL far rm
                3: case (s3)

                    0: begin s3 <= 1; ea <= ea + 2; ip <= op1; op1 <= ip; op2 <= seg[SEG_CS]; if (i_size == 0) fn <= UNDEF; end
                    1: begin s3 <= 2; ea <= ea + 1; wb_data <= i_data; fnext <= INSTR; end
                    2: begin s3 <= 3; fn <= PUSH; seg[SEG_CS] <= {i_data, wb_data[7:0]}; wb_data <= op2;  end
                    3: begin s3 <= 4; fn <= PUSH; wb_data <= op1; end
                    4: begin fn <= START; end

                endcase

                // JMP rm
                4: begin ip <= op1; fn <= i_size ? START : UNDEF; end

                // JMP far rm
                5: case (s3)

                    0: begin s3 <= 1; ea <= ea + 2; ip <= op1; if (i_size == 0) fn <= UNDEF; end
                    1: begin s3 <= 2; ea <= ea + 1; wb_data <= i_data; end
                    2: begin fn <= START;           seg[SEG_CS] <= {i_data, wb_data[7:0]}; end

                endcase

                // PUSH rm
                6: begin wb_data <= op1; fn <= PUSH; end
                7: begin fn <= UNDEF; end

            endcase
            8'b1010101x: case (s3)          // STOSx

                0: begin // STOSB

                    s3  <= i_size ? 1 : 2;
                    bus <= 1;
                    we  <= 1;
                    ea  <= r16[REG_DI];
                    o_data      <= r16[REG_AX][7:0];
                    segment_id  <= SEG_ES;

                end
                1: begin // STOSW

                    s3 <= 2;
                    we <= 1;
                    ea <= ea + 1;
                    o_data <= r16[REG_AX][15:8];

                end
                2: begin

                    we <= 0;
                    fn <= rep[1] ? REPF : START;
                    bus <= 0;

                    wb      <= 1;
                    wb_reg  <= REG_DI;
                    wb_data <= flags[DF] ? r16[REG_DI] - (i_size + 1) : r16[REG_DI] + (i_size + 1);
                    i_size  <= 1;

                end

            endcase
            8'b1010110x: case (s3)          // LODSx

                0: begin s3 <= 1; bus <= 1; ea <= r16[REG_SI]; end
                1: begin s3 <= i_size ? 2 : 3;

                    wb      <= 1;
                    wb_data <= i_data;
                    wb_reg  <= REG_AL;
                    i_size  <= 0;
                    ea      <= ea + 1;

                end
                2: begin s3 <= 3; wb <= 1; wb_data <= i_data; wb_reg <= REG_AH; end
                3: begin

                    fn  <= rep[1] ? REPF : START;
                    bus <= 0;

                    wb      <= 1;
                    wb_reg  <= REG_SI;
                    wb_data <= flags[DF] ? r16[REG_SI] - (opcode[0] + 1) : r16[REG_SI] + (opcode[0] + 1);
                    i_size  <= 1;

                end

            endcase
            8'b1010010x: case (s3)          // MOVSx

                // Загрузка 8 или 16 бит DS:SI
                0: begin s3 <= 1; ea <= r16[REG_SI]; bus <= 1; end
                1: begin s3 <= i_size ? 2 : 3; wb_data <= i_data; ea <= ea + 1; end
                2: begin s3 <= 3; wb_data[15:8] <= i_data; end

                // Запись 8 или 16 бит ES:DI
                3: begin s3 <= i_size ? 4 : 5;

                    we <= 1;
                    ea <= r16[REG_DI];
                    segment_id <= SEG_ES;
                    o_data     <= wb_data[7:0];

                end
                4: begin s3 <= 5; we <= 1; ea <= ea + 1; o_data <= wb_data[15:8]; end

                // Инкремент или декремент SI
                5: begin s3 <= 6; we <= 0; bus <= 0;

                    wb      <= 1;
                    wb_reg  <= REG_SI;
                    wb_data <= flags[DF] ? r16[REG_SI] - (opcode[0] + 1) : r16[REG_SI] + (opcode[0] + 1);
                    i_size  <= 1;

                end

                // Инкремент или декремент DI
                6: begin s3 <= 6;

                    wb      <= 1;
                    wb_reg  <= REG_DI;
                    wb_data <= flags[DF] ? r16[REG_DI] - (opcode[0] + 1) : r16[REG_DI] + (opcode[0] + 1);

                    // Использование REP:
                    fn  <= rep[1] ? REPF : START;

                end

            endcase
            8'b1010011x: case (s3)          // CMPSx

                0: begin s3 <= 1; bus <= 1; ea <= r16[REG_SI]; alu <= ALU_SUB; end
                1: begin s3 <= i_size ? 2 : 3; op1 <= i_data; ea <= ea + 1; end
                2: begin s3 <= 3; op1[15:8] <= i_data; end
                3: begin s3 <= 4;  segment_id <= SEG_ES; ea <= r16[REG_DI]; end
                4: begin s3 <= i_size ? 5 : 6; op2 <= i_data; ea <= ea + 1; end
                5: begin s3 <= 6; op2[15:8] <= i_data; end

                // Инкремент или декремент SI
                6: begin s3 <= 7;

                    wf      <= 1;
                    wb_flag <= alu_f;
                    bus     <= 0;
                    wb      <= 1;
                    wb_reg  <= REG_SI;
                    wb_data <= flags[DF] ? r16[REG_SI] - (opcode[0] + 1) : r16[REG_SI] + (opcode[0] + 1);
                    i_size  <= 1;

                end

                // Инкремент или декремент DI
                7: begin

                    wb      <= 1;
                    rep_ft  <= 1;       // Проверять на REPNZ или REPZ
                    wb_reg  <= REG_DI;
                    wb_data <= flags[DF] ? r16[REG_DI] - (opcode[0] + 1) : r16[REG_DI] + (opcode[0] + 1);

                    // Использование REP:
                    fn  <= rep[1] ? REPF : START;

                end

            endcase
            8'b1010111x: case (s3)          // SCASx

                0: begin s3 <= 1;

                    bus <= 1;
                    alu <= ALU_SUB;
                    op1 <= r16[REG_AX];
                    ea  <= r16[REG_DI];
                    segment_id <= SEG_ES;

                end
                1: begin s3 <= i_size ? 2 : 3; op2 <= i_data; ea <= ea + 1; end
                2: begin s3 <= 3; op2[15:8] <= i_data; end

                // Инкремент или декремент SI
                3: begin s3 <= 4;

                    wf      <= 1;
                    wb_flag <= alu_f;
                    bus     <= 0;
                    wb      <= 1;
                    wb_reg  <= REG_SI;
                    wb_data <= flags[DF] ? r16[REG_SI] - (opcode[0] + 1) : r16[REG_SI] + (opcode[0] + 1);
                    i_size  <= 1;

                end

                // Инкремент или декремент DI
                4: begin

                    wb      <= 1;
                    rep_ft  <= 1;       // Проверять на REPNZ или REPZ
                    wb_reg  <= REG_DI;
                    wb_data <= flags[DF] ? r16[REG_DI] - (opcode[0] + 1) : r16[REG_DI] + (opcode[0] + 1);

                    // Использование REP:
                    fn  <= rep[1] ? REPF : START;

                end

            endcase

        endcase

        // Расширенные инструции
        // -------------------------------------------------------------
        EXTEND: begin
        end

        // Прерывание intr
        // -------------------------------------------------------------
        INTR: case (s2)

            0: begin s2 <= 1;  fn <= PUSH; wb_data <= flags; fnext <= INTR; end
            1: begin s2 <= 2;  fn <= PUSH; wb_data <= seg[SEG_CS]; end
            2: begin s2 <= 3;  fn <= PUSH; wb_data <= ip; end
            3: begin s2 <= 4;  ea <= {intr, 2'b00}; segment_id[2] <= 1; bus <= 1; end
            4: begin s2 <= 5;  ea <= ea + 1; ip[ 7:0] <= i_data; end
            5: begin s2 <= 6;  ea <= ea + 1; ip[15:8] <= i_data; end
            6: begin s2 <= 7;  ea <= ea + 1; seg[SEG_CS][ 7:0] <= i_data; end
            7: begin bus <= 0; ea <= ea + 1; seg[SEG_CS][15:8] <= i_data; fn <= START; end

        endcase

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

        // Выполнение инструкции REP
        REPF: case (s4)

            // Уменьшить CX - 1
            0: begin s4 <= 1; wb_reg <= REG_CX; wb_data <= r16[REG_CX] - 1; wb <= 1; i_size <= 1; end
            1: begin

                // CX=0, повтор закончен
                if (r16[REG_CX] == 0) fn <= START;
                // REPNZ|REPZ
                else if (rep_ft) begin if (rep[0] == flags[ZF]) ip <= ip_start; end
                // REP:
                else ip <= ip_start;

                fn <= START;

            end

        endcase

        // Деление op1 на op2, i_size -> wb_data
        // DIV: case (s5)
        // endcase

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

// ---------------------------------------------------------------------
// Сдвиговый регистр
// ---------------------------------------------------------------------

reg [15:0] rot_r;
reg [11:0] rot_f;

always @* begin

    rot_f = flags;

    case (alu)

        ALU_ROL: rot_r = i_size ? {op1[14:0], op1[15]} : {op1[6:0], op1[7]};
        ALU_ROR: rot_r = i_size ? {op1[0], op1[15:1]}  : {op1[0], op1[7:1]};
        ALU_RCL: rot_r = i_size ? {op1[14:0], flags[CF]} : {op1[6:0], flags[CF]};
        ALU_RCR: rot_r = i_size ? {flags[CF], op1[15:1]}  : {flags[CF], op1[7:1]};
        ALU_SHL,
        ALU_SAL: rot_r = i_size ? {op1[14:0], 1'b0} : {op1[6:0], 1'b0};
        ALU_SHR: rot_r = i_size ? {1'b0, op1[15:1]}  : {1'b0, op1[7:1]};
        ALU_SHR: rot_r = i_size ? {op1[15], op1[15:1]} : {op1[7], op1[7:1]};

    endcase

    // Флаг CF
    rot_f[CF] = alu[0] ? op1[0] : op1[alu_top];

    // Флаг OF
    case (alu)

        ALU_ROL,
        ALU_RCL,
        ALU_SAL,
        ALU_SHL: rot_f[OF] = op1[alu_top] ^ op1[alu_top - 1];
        ALU_ROR,
        ALU_RCR: rot_f[OF] = rot_r[alu_top] ^ rot_r[alu_top - 1];
        ALU_SHR: rot_f[OF] = op1[alu_top];
        ALU_SAR: rot_f[OF] = 1'b0;

    endcase

    // S, Z, P для 4 инструкции
    if (alu == ALU_SHL || alu == ALU_SHR || alu == ALU_SAL || alu == ALU_SHR) begin

        rot_f[SF] = rot_r[alu_top];
        rot_f[ZF] = i_size ? (rot_r[15:0] == 0) : (rot_r[7:0] == 0);
        rot_f[PF] = ~^rot_r[7:0];

    end

end

endmodule

