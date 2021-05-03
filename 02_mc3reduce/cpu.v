module cpu(

    input   wire        reset,      // Сброс процессора

    /* Стандартные входы-выходы */
    input   wire        clk,        // 100 мегагерц
    input   wire        clk25,      // 25 мегагерц
    input   wire [7:0]  i,          // Data In (16 бит)
    output  reg  [7:0]  o,          // Data Out,
    output  wire [15:0] a,          // Address 32 bit
    output  reg         w,          // Запись [o] на HIGH уровне wm

    /* Работа с портами ввода-вывода */
    output  reg  [15:0] port_addr,
    input   wire [15:0] port_in,
    output  reg  [15:0] port_out,
    output  reg         port_bit,   /* Битность */
    output  reg         port_clk,   /* Запись в порт */
    output  reg         port_read   /* Чтение из порта */

);

`define INIT         0       // Исходное положение
`define MODRM        1       // Фаза декодирования ModRM байта
`define EXEC         2       // Исполнение инструкции

/* Описатели процедур */
`define SUB_NORMAL      0       // Нормальное исполнение кода
// Процедура записи WReg/CBit в [ea]
`define SUB_WRITE_MEM   1
`define SUB_WRITE_MEM2  2
// Запись в стек
`define SUB_PUSH        3
`define SUB_PUSH2       4
`define SUB_PUSH3       5
// Чтение из стека
`define SUB_POP         6
`define SUB_POP2        7
`define SUB_POP3        8

// Указатель на код или данные
assign a = sw ? ea : ip;

wire __sig = m == 1'b0 && routine == 1'b0;

initial begin o = 8'h00; w = 1'b0; port_addr = 1'b0; port_out = 1'b0; port_bit = 1'b0; port_clk = 1'b0; port_read = 1'b0; end

// Состояние процессора
// ---------------------------------------------------------------------
reg [1:0]  m  = 1'b0;           /* Текущее машинное состояние */
reg        sw = 1'b0;           /* Переключение на альтернативный адрес */
reg [15:0] ea = 16'h0000;       /* Альтернативный/эффективный адрес */
reg [ 7:0] opcode = 8'h00;      /* Принятый опкод */
reg [ 7:0] modrm  = 8'h00;      /* Принятый байт ModRM */
reg [ 2:0] modrm_stage = 1'b0;  /* Стадия разбора ModRM */
reg [ 3:0] routine = 1'b0;      /* Микроисполнение процедур */
reg [ 2:0] micro = 1'b0;        /* Микрокод */

// Набор регистров
// ---------------------------------------------------------------------
reg [2:0]  CReg = 3'b000;   /* Выбор регистра */
reg [2:0]  CAlu = 3'b000;   /* Номер режима АЛУ */
reg        CBit  = 1'b0;    /* Выбор битности (0=8, 1=16) */
reg        CBitT = 1'b0;    /* Временный CBit */
reg        DBit = 1'b0;     /* Выбор направления (0=rm,reg; 1=reg,rm) */
reg [2:0]  SMod = 1'b0;     /* Номер инструкции сдвига */
reg [4:0]  SCnt = 1'b0;     /* Количество сдвигов (от 0 до 31) */
reg [2:0]  CSel = 1'b0;     /* Выбор условия (основного) */
reg [15:0] DReg;            /* Результат выборки */
reg [15:0] WReg = 1'b0;     /* Для записи в регистр */
reg        WR   = 1'b0;     /* Разрешение записи в регистр */

reg [15:0] op1 = 1'b0;      /* Операнд 1: Destination */
reg [15:0] op2 = 1'b0;      /* Операнд 2: Source */

/* Регистры процессора */
reg [15:0] ax    = 16'h2F3F;
reg [15:0] cx    = 16'h0002;
reg [15:0] dx    = 16'h64EA;
reg [15:0] bx    = 16'hB002;
reg [15:0] sp    = 16'hC000;
reg [15:0] bp    = 16'h0000;
reg [15:0] si    = 16'h1234;
reg [15:0] di    = 16'h0000;
                //     ODIT SZ A  P C
reg [11:0] flags = 12'b0000_0000_0000;
reg [15:0] ip    = 16'hFFF0;

/* Текущий регистр: DReg = GetValue(CReg, CBit) */
always @* begin
    case (CReg)
        3'h0: DReg = CBit ? ax : {8'h00, ax[7:0]};
        3'h1: DReg = CBit ? cx : {8'h00, cx[7:0]};
        3'h2: DReg = CBit ? dx : {8'h00, dx[7:0]};
        3'h3: DReg = CBit ? bx : {8'h00, bx[7:0]};
        3'h4: DReg = CBit ? sp : {8'h00, ax[15:8]};
        3'h5: DReg = CBit ? bp : {8'h00, cx[15:8]};
        3'h6: DReg = CBit ? si : {8'h00, dx[15:8]};
        3'h7: DReg = CBit ? di : {8'h00, bx[15:8]};
    endcase
end

/* Запись результа на обратном фронте в регистр */
always @(negedge clk25) if (WR)
case (CReg)
    3'h0: if (CBit) ax <= WReg; else ax[7:0] <= WReg[7:0];
    3'h1: if (CBit) cx <= WReg; else cx[7:0] <= WReg[7:0];
    3'h2: if (CBit) dx <= WReg; else dx[7:0] <= WReg[7:0];
    3'h3: if (CBit) bx <= WReg; else bx[7:0] <= WReg[7:0];
    3'h4: if (CBit) sp <= WReg; else ax[15:8] <= WReg[7:0];
    3'h5: if (CBit) bp <= WReg; else cx[15:8] <= WReg[7:0];
    3'h6: if (CBit) si <= WReg; else dx[15:8] <= WReg[7:0];
    3'h7: if (CBit) di <= WReg; else bx[15:8] <= WReg[7:0];
endcase

// ---------------------------------------------------------------------
// Арифметико-логическое устройство (стандартное)
// ---------------------------------------------------------------------

reg [16:0] Ar;   /* Результат исполнения АЛУ */
reg [11:0] Af;   /* Флаги */

// Некоторые флаги АЛУ
wire Zero8  = ~|Ar[7:0];
wire Zero16 = ~|Ar[15:8] && Zero8;
wire Sign8  =   Ar[7];
wire Sign16 =   Ar[15];
wire Parity = ~^Ar[7:0];

/* Специальный случай: переполнение ADD/SUB */
wire ADD_Overflow8  = (op1[7]  ^ op2[7]  ^ 1'b1) & (op2[7]  ^ Ar[7]);
wire ADD_Overflow16 = (op1[15] ^ op2[15] ^ 1'b1) & (op2[15] ^ Ar[15]);
wire SUB_Overflow8  = (op1[7]  ^ op2[7]        ) & (op2[7]  ^ Ar[7]);
wire SUB_Overflow16 = (op1[15] ^ op2[15]       ) & (op2[15] ^ Ar[15]);

always @* begin

    case (CAlu)

        /* ADD */  3'h0: Ar = op1 + op2;
        /* OR  */  3'h1: Ar = op1 | op2;
        /* ADC */  3'h2: Ar = op1 + op2 + flags[0];
        /* SBB */  3'h3: Ar = op1 - op2 - flags[0];
        /* AND */  3'h4: Ar = op1 & op2;
        /* SUB */  3'h5: Ar = op1 - op2;
        /* XOR */  3'h6: Ar = op1 ^ op2;
        /* CMP */  3'h7: Ar = op1 - op2;

    endcase

    case (CAlu)

        /* ADD, ADC */
        3'h0, 3'h2:
            Af = {
                /* 11 OF */ CBit ? ADD_Overflow16 : ADD_Overflow8,
                /* 10 DF */ flags[10],
                /*  9 IF */ flags[9],
                /*  8 TF */ flags[8],
                /*  7 SF */ CBit ? Sign16 : Sign8,
                /*  6 ZF */ CBit ? Zero16 : Zero8,
                /*  5  - */ 1'b0,
                /*  4 AF */ op1[3:0] + op2[3:0] + (CAlu == 3'h2 /* ADC */ ? flags[0] : 1'b0) >= 5'h10,
                /*  3  - */ 1'b0,
                /*  2 PF */ Parity,
                /*  1  - */ 1'b1,
                /*  0 CF */ CBit ? Ar[16] : Ar[8]
            };

        /* SBB, SUB, CMP */
        3'h3, 3'h5, 3'h7:
            Af = {
                /* 11 OF */ CBit ? SUB_Overflow16 : SUB_Overflow8,
                /* 10 DF */ flags[10],
                /*  9 IF */ flags[9],
                /*  8 TF */ flags[8],
                /*  7 SF */ CBit ? Sign16 : Sign8,
                /*  6 ZF */ CBit ? Zero16 : Zero8,
                /*  5  - */ 1'b0,
                /*  4 AF */ op1[3:0] < op2[3:0] + (CAlu == 3'h3 /* SBB */ ? flags[0] : 1'b0),
                /*  3  - */ 1'b0,
                /*  2 PF */ Parity,
                /*  1  - */ 1'b1,
                /*  0 CF */ CBit ? Ar[16] : Ar[8]
            };

        /* OR, XOR, AND */
        default:
            Af = {
                /* 11 OF */ 1'b0,
                /* 10 DF */ flags[10],
                /*  9 IF */ flags[9],
                /*  8 TF */ flags[8],
                /*  7 SF */ CBit ? Sign16 : Sign8,
                /*  6 ZF */ CBit ? Zero16 : Zero8,
                /*  5  - */ 1'b0,
                /*  4 AF */ Ar[4], /* Undefined */
                /*  3  - */ 1'b0,
                /*  2 PF */ Parity,
                /*  1  - */ 1'b1,
                /*  0 CF */ 1'b0
            };

    endcase

end

// Решение о переходе по выбранному условию
wire condition =
    CSel == 3'b000 ? flags[11] :                          // OF=1
    CSel == 3'b001 ? flags[0] :                           // CF=1
    CSel == 3'b010 ? flags[6] :                           // ZF=1
    CSel == 3'b011 ? (flags[0] | flags[6]) :              // CF=1 OR ZF=1
    CSel == 3'b100 ? flags[7] :                           // SF=1
    CSel == 3'b101 ? flags[2] :                           // PF=1
    CSel == 3'b110 ? (flags[7] ^ flags[11]) :             // SF != OF
                     (flags[7] ^ flags[11]) | (flags[6]); // (ZF=1) OR (SF != OF)

reg [15:0] Sr;
reg        Sc; // Carry

/* Инструкции сдвига (Данные на вход: op1, CBit) */
always @* begin

    case (SMod)

        /* ROL */ 3'h0: Sr = CBit ? {op1[14:0], op1[15]}   : {op1[6:0], op1[7]};
        /* ROR */ 3'h1: Sr = CBit ? {op1[0],    op1[15:1]} : {op1[0],   op1[7:1]};
        /* RCL */ 3'h2: Sr = CBit ? {op1[14:0], flags[0]}  : {op1[6:0], flags[0]};
        /* RCR */ 3'h3: Sr = CBit ? {flags[0],  op1[15:1]} : {flags[0], op1[7:1]};
        /* SHL */ 3'h4, 3'h6:
                        Sr = CBit ? {op1[14:0], 1'b0}      : {op1[6:0], 1'b0};
        /* SHR */ 3'h5: Sr = CBit ? {1'b0,      op1[15:1]} : {1'b0,     op1[7:1]};
        /* SAR */ 3'h7: Sr = CBit ? {op1[15],   op1[15:1]} : {op1[7],   op1[7:1]};

    endcase

    case (SMod)

        /* ROL, RCL, SHL, SAL */
        3'h0, 3'h2, 3'h4, 3'h6: Sc = CBit ? op1[15] : op1[7];

        /* ROR */
        3'h1, 3'h3, 3'h5, 3'h7: Sc = op1[0];

    endcase

end

// ---------------------------------------------------------------------
// Главные такты
// ---------------------------------------------------------------------

always @(posedge clk25) begin

    /* Сброс */
    if (reset) begin

        ip <= 16'hFFF0;
        routine <= 1'b0;
        {sw, m} <= 2'b00;

    end

    /* Микропроцедуры */
    else case (routine)

        /* Запись WReg (битность CBit) в память [ea]. После записи CBit=0 */
        `SUB_WRITE_MEM:  begin o <= WReg[7:0]; w <= 1'b1; routine <= `SUB_WRITE_MEM2; end
        `SUB_WRITE_MEM2: begin

            routine <= CBit? `SUB_WRITE_MEM2 : `SUB_NORMAL;
            o    <= WReg[15:8];
            ea   <= ea + 1'b1;
            w    <= CBit; /* Включить запись, если 16 бит, либо выключить */
            sw   <= CBit; /* Отключить указатель на EA если достигли 8 бит записи */
            CBit <= 1'b0;

        end

        /* Запись WReg в стек (r16): sp -= 2; mov [sp], WReg */
        `SUB_PUSH:  begin routine <= `SUB_PUSH2;  o  <= WReg[7:0];    CBit <= 1'b1; ea <= sp - 2;    sw   <= 1'b1;   w <= 1'b1; end
        `SUB_PUSH2: begin routine <= `SUB_PUSH3;  o  <= WReg[15:8];   WR   <= 1'b1; ea <= ea + 1'b1; WReg <= sp - 2; CReg <= 3'h4; end
        `SUB_PUSH3: begin routine <= `SUB_NORMAL; {w, sw} <= {2'b00}; WR   <= 1'b0; end

        /* Чтение из стека в WReg */
        `SUB_POP:  begin routine <= `SUB_POP2;   WReg <= sp + 2'h2; ea <= sp;        WR <= 1'b1; {CReg, sw, CBit} <= {3'h4, 2'b11}; end
        `SUB_POP2: begin routine <= `SUB_POP3;   WReg[7:0]  <= i;   ea <= ea + 1'b1; WR <= 1'b0; end
        `SUB_POP3: begin routine <= `SUB_NORMAL; WReg[15:8] <= i;   sw <= 1'b0; end

        /* Нормальное исполнение кода */
        default: case (m)

            /* Декодер, распределение */
            `INIT: begin

                opcode      <= i;    /* Запись опкода для использования */
                micro       <= 1'b0; /* Сброс микрокода */
                modrm_stage <= 1'b0; /* Сброс стадии обработки modrm */
                WR          <= 1'b0; /* Сброс записи в регистр на обратном фронте */
                ip     <= ip + 1'b1; /* К следующей инструкции */

                casex (i)

                    /* Выбор режима АЛУ, сканирование байта ModRM */
                    8'b00_xxx_0xx: begin

                        CAlu <= i[5:3];
                        {DBit, CBit} <= i[1:0];
                        m    <= `MODRM;

                    end

                    /* АЛУ Acc + Imm8,16 */
                    8'b00_xxx_10x: begin

                        CReg <= 3'h0;   /* AL или AX */
                        CAlu <= i[5:3]; /* Режим АЛУ */
                        {DBit, CBit} <= i[1:0];
                        m    <= `EXEC;

                    end

                    /* Групповые инструкции АЛУ; TEST rm, r; XCHG rm, r */
                    8'b1000_0xxx,
                    8'b1111_011x: begin

                        /* Направление всегда rm,reg */
                        {DBit, CBit} <= {1'b0, i[0]};
                        CAlu <= 3'h4; /* AND */
                        m <= `MODRM;

                    end

                    /* MOV ModRM */
                    8'b1000_10xx: begin

                        {DBit, CBit} <= i[1:0];
                        m <= `MODRM;

                    end

                    /* MOV reg, i8/16 */
                    8'b1011_xxxx: begin

                        /* Битность в 4-м бите, 2:0 - номер регистра */
                        {CBit, CReg} <= i[3:0];
                        m <= `EXEC;

                    end

                    /* MOV rm, i8/16 */
                    8'b1100_011x: begin

                        {DBit, CBit} <= {1'b0, i[0]};
                        m <= `MODRM;

                    end

                    /* RET [i16] */
                    8'b1100_001x: begin

                        ea <= sp;
                        sw <= 1'b1;
                        m  <= `EXEC;

                    end

                    /* J<ccc> rel8 */
                    8'b0111_xxxx: begin

                        CSel <= i[4:1];
                        m <= `EXEC;

                    end

                    /* Установка флагов */
                    8'b1111_0101: flags[0] <= ~flags[0]; /* CMC */
                    8'b1111_100x: flags[0] <= i[0];      /* CLC/STC */
                    8'b1111_101x: flags[9] <= i[0];      /* CLI/STI */
                    8'b1111_110x: flags[10] <= i[0];     /* CLD/STD */
                    8'b1001_0000: begin /* NOP */ end

                    /* CBW, CWD */
                    8'b1001_100x: begin

                        WReg <= i[0] ? {16{ax[15]}} : {{8{ax[7]}}, ax[7:0]};
                        CBit <= 1'b1;
                        CReg <= i[0] ? 3'h2 : 3'h0;
                        m <= `EXEC;

                    end

                    /* INC/DEC r16 */
                    8'b0100_xxxx: begin

                        {CReg, CBit} <= {i[2:0], 1'b1};
                        op2   <= 1'b1;
                        CAlu  <= i[3] ? /*SUB*/ 3'h5 : /*ADD*/ 3'h0;
                        m     <= `EXEC;

                    end

                    /* PUSH/POP r16 */
                    8'b0101_xxxx: begin

                        {CBit, CReg} <= {1'b1, i[2:0]};
                        m <= `EXEC;

                    end

                    /* XCHG r16 */
                    8'b1001_0xxx: begin

                        {CBit, CReg} <= {1'b1, i[2:0]}; /* Извлечем регистр для записи в AX */
                        op1 <= ax; /* Сохранение старого значения AX */
                        m   <= `EXEC;

                    end

                    /* PUSHF */
                    8'b1001_1100: begin

                        WReg <= flags;
                        routine <= `SUB_PUSH;

                    end

                    /* POPF */
                    8'b1001_1101: begin

                        routine <= `SUB_POP;
                        m <= `EXEC;

                    end

                    /* IN/OUT */
                    8'b1110_x1xx: begin

                        CBit      <= i[0];
                        port_bit  <= i[0];
                        port_addr <= dx;
                        m <= `EXEC;

                    end

                    /* Операции сдвига */
                    8'b1101_00xx: begin

                        {DBit, CBit} <= {1'b0, i[0]};
                        m <= `MODRM;

                    end

                    /* A0-A3 MOV moffset <-> AL/AX */
                    8'b1010_00xx: begin

                        {CReg, CBit} <= {3'b000, i[0]};
                        m <= `EXEC;

                    end

                    /* XLATB */
                    8'b1101_0111: begin

                        ea <= bx + {8'h00, ax[7:0]};
                        {CReg, CBit} <= {3'h0, 1'b0}; /* AL */
                        sw <= 1'b1;
                        m  <= `EXEC;

                    end

                    /* TEST al/ax, i8/16 */
                    8'b1010_100x: begin

                        {CReg, CBit} <= {3'b000, i[0]};
                        CAlu <= 3'h4; /* AND */
                        m <= `EXEC;

                    end

                    /* SAHF/LAHF */
                    8'b1001_1110: flags <= ax[15:8];
                    8'b1001_1111: begin

                        {CBit, CReg} <= {1'h0, 3'h4}; // CReg=AH
                        WReg <= flags;
                        WR <= 1'b1;

                    end

                    /* Все другие опкоды - на исполнение */
                    default: m <= `EXEC;

                endcase

            end

            /* Разбор байта ModRM */
            `MODRM: case (modrm_stage)

                /* Стадия 1: Считывание байта */
                3'h0: begin

                    /* Пишем на будущее */
                    modrm <= i;

                    /* Разбор указателя на память (16 бит) */
                    case (i[2:0])
                        3'h0: ea <= bx + si;
                        3'h1: ea <= bx + di;
                        3'h2: ea <= bp + si;
                        3'h3: ea <= bp + di;
                        3'h4: ea <= si;
                        3'h5: ea <= di;
                        3'h6: ea <= (i[7:6] == 2'b00) ? 16'h0000 : bp;
                        3'h7: ea <= bx;
                    endcase

                    /* (@todo) Здесь должен быть сегмент, но его нет пока */

                    /* Начинаем считывать регистр из reg-секции modrm */
                    CReg <= i[5:3];

                    /* Переключимся сразу на память, если mod = 00 и rm != 6 */
                    sw <= (i[7:6] == 2'b00) && (i[2:0] != 3'h6);

                    /* Перейти к следующему байту */
                    ip <= ip + 1'b1;

                    /* К следующему шагу */
                    modrm_stage <= 3'h1;

                end

                /* Считывание регистра, либо, возможно, данных из памяти */
                3'h1: begin

                    /* В зависимости от выбранного D (направления), пишется операнд из регистра (8/16 bit) */
                    op1 <= DBit ? DReg : i;
                    op2 <= DBit ? i : DReg;

                    /* В случае, если регистр выбран как операнд, а не память */
                    CReg <= modrm[2:0];

                    /* Решение, что делать дальше */
                    case (modrm[7:6])

                        /* Либо завершить чтение из памяти, либо переход к disp16 */
                        2'b00: begin

                            /* Либо прочитать 16-битный disp16 */
                            if (modrm[2:0] == 3'h6) begin ip <= ip + 1'b1; ea[7:0] <= i; modrm_stage <= 3'h3; end

                            /* 16-битный операнд: читать старшие 8 бит */
                            else if (CBit) begin ea <= ea + 1'b1; modrm_stage <= 3'h5; end

                            /* Либо перейти к исполнению */
                            else begin m <= `EXEC; end

                        end

                        /* Disp8: Знаковое расширение 8 до 16 бит. Переход к считыванию данных в операнд */
                        2'b01: begin modrm_stage <= 3'h4; ip <= ip + 1'b1; ea <= ea + {{8{i[7]}}, i[7:0]}; sw <= 1'b1; end

                        /* Disp16: Прибавить нижние 8 бит, и переход к чтению 16 битной части */
                        2'b10: begin modrm_stage <= 3'h3; ip <= ip + 1'b1; ea <= ea + {8'h00, i[7:0]}; end

                        /* Прочитать регистр вместо памяти, и выйти к исполнению */
                        2'b11: begin modrm_stage <= 3'h2; end

                    endcase

                end

                /* Считывание второго регистра из modrm и переход к исполнению */
                3'h2: begin

                    op1 <= DBit ? op1 : DReg;
                    op2 <= DBit ? DReg : op2;
                    m <= `EXEC;

                end

                /* Прочитать +disp16 */
                3'h3: begin

                   ea[15:8] <= ea[15:8] + i;
                   ip <= ip + 1'b1;
                   sw <= 1'b1;
                   modrm_stage <= 3'h4;

                end

                /* Считывание 8 или 16 бит из [ea] */
                3'h4: begin

                    /* Нижние 8 бит читать всегда */
                    op1 <= DBit ? op1 : i;
                    op2 <= DBit ? i : op2;

                    /* Есть 16 бит? Прочесть их */
                    if (CBit) begin modrm_stage <= 3'h5; ea <= ea + 1'b1; end

                    /* Либо перейти к исполнению */
                    else m <= `EXEC;

                end

                /* Читать старшие 8 бит */
                3'h5: begin

                    op1[15:8] <= DBit ? op1[15:8] : i;
                    op2[15:8] <= DBit ? i : op2[15:8];

                    /* Вернуть ea, чтобы знать, куда их писать обратно */
                    ea <= ea - 1'b1;
                    m <= `EXEC;

                end

            endcase

            /* Исполнение инструкции */
            `EXEC: casex (opcode)

                /* Инструкции АЛУ ModRM */
                8'b00_xxx_0xx: begin

                    /* Не должно быть CMP */
                    if (CAlu < 3'h7) begin

                        /* Данные для записи */
                        WReg <= Ar;

                        /* (1) Пишем в регистр,
                           (2) Уже был выбран регистр */

                        if (modrm[7:6] == 2'b11 || DBit) begin

                            CReg <= DBit ? modrm[5:3] : modrm[2:0];
                            WR   <= 1'b1;
                            sw   <= 1'b0;

                        end

                        /* Иначе запись в память [ea] */
                        else routine <= `SUB_WRITE_MEM;

                    end

                    flags <= Af;
                    m     <= `INIT; /* Возврат обратно */

                end

                /* <ALU> al/ax, i8/i16 */
                8'b00_xxx_10x: case (micro)

                    /* Загрузка операнда в АЛУ */
                    3'h0: begin

                        micro <= 3'h1;
                        op1   <= DReg;      /* Загрузить AL/AX */
                        op2   <= i;         /* Загрузить нижние 8 бит */
                        ip    <= ip + 1'b1;

                    end

                    /* Расчет 8 бит */
                    3'h1: begin

                        micro <= 3'h2;
                        WR    <= CAlu != 3'h7;      /* Запись в регистр результата (кроме 7=CMP) */
                        WReg  <= Ar;                /* На запись 8/16 бит */
                        ip    <= ip + opcode[0];    /* IP+0, если записывали БАЙТ */
                        flags <= Af;

                        if (~CBit) m <= `INIT;      /* Если 8 бит, перейти к сканированию снова */
                        op2[15:8] <= i;             /* Подготовка 16-битного операнда */

                    end

                    /* Расчет 16 бит */
                    3'h2: begin

                        WReg  <= Ar;
                        flags <= Af;
                        m     <= `INIT;

                    end

                endcase

                /* GRP <ALU>, imm */
                8'b1000_00xx: case (micro)

                    /* Выборка АЛУ. Переключиться на память кода */
                    3'h0: begin sw <= 1'b0; micro <= 3'h1; CAlu <= modrm[5:3]; end

                    /* Чтение 8 бит Immediate */
                    3'h1: begin op2 <= i; micro <= 3'h2; ip <= ip + 1'b1; CBitT <= opcode[0]; end

                    /* Либо запись в регистр, либо в память, либо далее */
                    3'h2: begin

                        /* 16-битное, дополнительно читать */
                        if (CBitT) begin

                            /* В случае если это SignExtend опкод */
                            op2[15:8] <= opcode[1] ? {8{op2[7]}} : i;

                            /* Не добавлять +1 если это opcode[1:0] = 2'b11 */
                            if (opcode[1] == 1'b0)
                                ip <= ip + 1'b1;

                            /* Выйти к обработке */
                            CBitT     <= 1'b0;

                        end

                        /* Обработка результата */
                        else begin

                            WReg  <= Ar;
                            flags <= Af;
                            m     <= `INIT;

                            /* 8/16 бит, пишем результат в регистр (кроме CMP) */
                            if (modrm[7:6] == 2'b11) begin WR <= (CAlu != 3'h7); end

                            /* Либо 8/16 бит в память */
                            else begin sw <= 1'b1; routine <= `SUB_WRITE_MEM; end

                        end

                    end

                endcase

                /* 88-8B MOV <ModRM> */
                8'b1000_10xx: begin

                    WReg <= op2;
                    m    <= `INIT;

                    if (modrm[7:6] == 2'b11 || DBit) begin

                        CReg <= DBit ? modrm[5:3] : modrm[2:0];
                        WR   <= 1'b1;
                        sw   <= 1'b0;

                    end
                    else routine <= `SUB_WRITE_MEM;

                end

                /* B0-BF MOV reg, i8/16 */
                8'b1011_xxxx: case (micro)

                    /* 8-битный регистр */
                    3'h0: begin WReg <= i; WR <= 1'b1; micro <= 3'h1; ip <= ip + 1'b1; if (~CBit) m <= `INIT; end

                    /* 16-битный регистр */
                    3'h1: begin WReg[15:8] <= i; m <= `INIT; ip <= ip + 1'b1; end

                endcase

                /* MOV rm, i8/16 */
                8'b1100_011x: case (micro)

                    /* Инициализация */
                    3'h0: begin sw <= 1'b0; CReg <= modrm[2:0]; micro <= 3'h1; end

                    /* Сканирование i8/16 */
                    3'h1: begin

                        /* (1) Пришел сразу 8 бит, использовать сразу (2) Повторно, 16 бит */
                        if (~CBit) begin

                            CBit <= opcode[0]; /* Установить реальную битность */
                            WReg <= opcode[0] ? {i, WReg[7:0]} : i;  /* В зависимости от 8/16 */

                            if (modrm[7:6] == 2'b11) /* Пишем в регистр или память */
                                 begin WR <= 1'b1; end
                            else begin sw <= 1'b1; routine <= `SUB_WRITE_MEM; end

                            m <= `INIT; /* К следующему опкоду */

                        /* Сброс бита, для перехода к записи */
                        end else begin WReg <= i; CBit <= 1'b0; end

                        ip <= ip + 1'b1;

                    end

                endcase

                /* RET */
                8'b1100_001x: case (micro)

                    /* Записываем младший байт */
                    3'h0: begin

                        micro    <= 3'h1;

                        CBit     <= 1'b1;
                        ea       <= ea + 1'b1;
                        WReg     <= sp + 2'h2;

                        /* SP = SP + 2 */
                        {CBit, CReg, WR} <= {1'b1, 3'h4, 1'b1};

                        op1[ 7:0] <= i;

                    end

                    /* Записываем старший байт */
                    3'h1: begin

                        micro     <= 3'h2;
                        WR        <= 1'b0;
                        sw        <= 1'b0;
                        op1[15:8] <= i;

                        if (opcode[0]) begin m <= `INIT; ip <= {i, op1[7:0]}; end

                     end

                    /* SP = SP + Imm16 */
                    3'h2: begin WReg <= sp + i; ip <= ip + 1'b1; micro <= 3'h3; WR <= 1'b1; end
                    3'h3: begin WReg[15:8] <= WReg[15:8] + i; m <= `INIT; ip <= op1; end

                endcase

                /* CBW, CWD */
                8'b1001_100x: begin WR <= 1'b1; m <= `INIT; end

                /* JMP r16/r8 */
                8'b1110_10x1: case (micro)

                    3'h0: begin

                        if (~opcode[1]) /* rel16 */ begin op1 <= ip + i; ip <= ip + 1'b1; end
                        else begin ip <= ip + {{8{i[7]}}, i[7:0]} + 1'b1; m <= `INIT; end
                        micro <= 3'h1;

                    end

                    /* 16-битное относительное смещение */
                    3'h1: begin ip <= {op1[15:8] + i, op1[7:0]} + 2'h2; m <= `INIT; end

                endcase

                /* CALL r16 */
                8'b1110_1000: case (micro)

                    /* Подготовка записи в стек */
                    3'h0: begin

                        micro   <= 3'h1;
                        op1     <= ip + i;
                        ip      <= ip + 1'b1;
                        WReg    <= sp - 2'h2;
                        ea      <= sp - 2'h2;

                        {CBit, CReg, WR} <= { 1'b1, 3'h4, 1'b1 }; /* SP */

                    end

                    /* Записать в стек ip и перейти */
                    3'h1: begin

                        WR   <= 1'b0;
                        WReg <= ip + 1'b1;
                        ip   <= {op1[15:8] + i, op1[7:0]} + 2'h2;
                        sw   <= 1'b1;
                        routine <= `SUB_WRITE_MEM;
                        m    <= `INIT;

                    end

                endcase

                /* LOOP* инструкции */
                8'b1110_00xx: begin

                    /* JCXZ */
                    if (opcode[1:0] == 2'b11) begin

                        ip <= cx ? ip + 1'b1 : ({{8{i[7]}}, i[7:0]} + ip + 1'b1);

                    end else begin

                        WReg <= cx - 1'b1;

                        /* CX-- */
                        {CReg, CBit, WR} <= {3'h1, 1'b1, 1'b1};

                        /* Если CX=0, или если LOOPZ/NZ - то переход к следующей инструкции */
                        if (cx == 1'b1 || (!opcode[1] && (opcode[0] ^ flags[6]))) begin
                            ip <= ip + 1'b1;
                        end
                        else begin
                            ip <= ip + {{8{i[7]}}, i[7:0]} + 1'b1;
                        end

                    end

                    m <= `INIT;

                end

                /* INC/DEC */
                8'b0100_xxxx: case (micro)

                    3'h0: begin op1 <= DReg; micro <= 3'h1; end /* Прочесть op1 */
                    3'h1: begin WR <= 1'b1; WReg <= Ar; flags <= Af; m <= `INIT; end /* Записать в регистр */

                endcase

                /* PUSH r16 */
                8'b0101_0xxx: begin

                    WReg    <= DReg;
                    routine <= `SUB_PUSH;
                    m       <= `INIT;

                end

                /* POP r16 */
                8'b0101_1xxx: case (micro)

                    3'h0: begin routine <= `SUB_POP; micro <= 1'b1; end
                    3'h1: begin WR <= 1'b1; CReg <= opcode[2:0];  m <= `INIT; end

                endcase

                /* XCHG r16 */
                8'b1001_0xxx: case (micro)

                    3'h0: begin CReg <= 1'b0; WR <= 1'b1; WReg <= DReg; micro <= 1'b1; end /* Пишем R16 в AX */
                    3'h1: begin CReg <= opcode[2:0]; WReg <= op1; m <= `INIT; end   /* Пишем AX в регистр */

                endcase

                /* J<ccc> rel8 */
                8'b0111_xxxx: begin

                    /* Переход в зависимости от условия */
                    ip <= ip + ((condition ^ opcode[0]) ? {{8{i[7]}}, i[7:0]} + 2'h1 : 1'h1);
                    m  <= `INIT;

                end

                /* POPF */
                8'b1001_1101: begin

                    flags <= WReg;
                    m <= `INIT;

                end

                /* IN/OUT */
                8'b1110_x1xx: case (micro)

                    3'h0: begin

                        /* Возможно, чтение i8 */
                        if (~opcode[3]) begin port_addr <= i; ip <= ip + 1'b1; end

                        /* В случае записи в порт */
                        port_out  <= ax;
                        micro     <= 1'b1;
                        port_read <= ~opcode[1];

                    end

                    /* Если OUT - запись в порт */
                    3'h1: begin port_read <= 1'b0; port_clk <= opcode[1]; micro <= opcode[1] ? 2'h2 : 3'h3; end

                    /* Если IN - чтение из порта */
                    3'h2: begin port_clk <= 1'b0; CReg <= 4'h0; WReg <= port_in; WR <= ~opcode[1]; m <= `INIT; end

                    /* Для того, чтобы успело чтение из порта */
                    3'h3: micro <= 3'h2;

                endcase

                /* <Shift> rm, 1/cl */
                8'b1101_00xx: case (micro)

                    /* Расчет количества сдвигов */
                    3'h0: begin

                        micro <= 3'h1;
                        SMod  <= modrm[5:3];

                        casex (opcode[1:0])
                            2'b0x: SCnt <= 1'b1;
                            2'b10: begin SCnt <= cx[3:0]; if (cx[3:0] == 1'b0) m <= `INIT; end
                            2'b11: begin SCnt <= cx[4:0]; if (cx[4:0] == 1'b0) m <= `INIT; end
                        endcase

                    end

                    /* Выполнение инструкции сдвига */
                    3'h1: begin

                        /* Вычисление */
                        if (SCnt) begin

                            op1   <= Sr;
                            WReg  <= Sr;
                            flags <= {flags[11:1], Sc};
                            SCnt  <= SCnt - 1'b1;

                        end

                        /* Запись либо в регистр */
                        else if (modrm[7:6] == 2'b11) begin

                            WR   <= 1'b1;
                            CReg <= modrm[2:0];
                            m    <= `INIT;
                            sw   <= 1'b0;

                        end

                        /* Либо в память */
                        else routine <= `SUB_WRITE_MEM;

                    end

                endcase

                /* XCHG rm, r8 */
                8'b1000_011x: case (micro)

                    /* Запись операнда 1 */
                    3'h0: begin

                        WReg  <= op2;
                        op2   <= op1;
                        micro <= 3'h1;

                        /* Если пишется в регистр, то писать должен op2 в этот регистр */
                        if (modrm[7:6] == 2'b11) begin

                            CReg <= modrm[2:0];
                            WR   <= 1'b1;

                        end
                        else routine <= `SUB_WRITE_MEM;

                    end

                    /* В любом случае в регистр */
                    3'h1: begin

                        CBit <= opcode[0];
                        CReg <= modrm[5:3];
                        WReg <= op2;
                        WR   <= 1'b1;
                        m    <= `INIT;

                    end

                endcase

                /* XLATB */
                8'b1101_0111: begin

                    WR <= 1'b1;
                    sw <= 1'b0;
                    WReg <= i;
                    m <= `EXEC;

                end

                /* A0-A3 MOV moffset <-> AL/AX */
                8'b1010_00xx: case (micro)

                    /* Прочесть адрес moffset */
                    3'h0: begin micro <= 3'h1; ea[7:0]  <= i; ip <= ip + 1'b1; end
                    3'h1: begin micro <= 3'h2; ea[15:8] <= i; ip <= ip + 1'b1; sw <= 1'b1; end

                    /* Писать в память, если запись идет в moffset */
                    3'h2: if (opcode[1]) begin WReg <= DReg; routine <= routine <= `SUB_WRITE_MEM; end
                          /* Либо в регистр */
                          else begin micro <= 3'h3; WReg <= i; WR <= 1'b1; ea <= ea + 1'b1; sw <= opcode[0];
                                     if (~opcode[0]) m <= `INIT; end

                    /* 16-битный AX */
                    3'h3: begin WReg[15:8] <= i; sw <= 1'b0; m <= `INIT; end

                endcase

                /* TEST rm, r8/16 */
                8'b1000_010x: begin

                    flags <= Af;
                    sw <= 1'b0;
                    m <= `INIT;

                end

                /* TEST al/ax, i8/16 */
                8'b1010_100x: case (micro)

                    3'h0: begin micro <= 3'h1; op1 <= DReg; op2 <= i; CBitT <= CBit; ip <= ip + 1'b1; end
                    3'h1: if (CBitT) begin CBitT <= 1'b0; op2[15:8] <= i; ip <= ip + 1'b1; end
                          else       begin flags <= Af; m <= `INIT; end

                endcase

                /* GRP #1 */
                8'b1111_011x: case (modrm[5:3])

                    // TEST rm, i8/16 */
                    3'b000, 3'b001: begin

                        case (micro)

                            3'h0: begin micro <= 3'h1; sw  <= 1'b0;  end
                            3'h1: begin micro <= 3'h2; op2 <= i; ip <= ip + 1'b1; CBitT <= CBit; end
                            3'h2: if (CBitT) begin CBitT <= 1'b0; ip <= ip + 1'b1; op2[15:8] <= i; end
                                  else       begin flags <= Af; m <= `INIT; end

                        endcase

                    end

                endcase

            endcase

        endcase

    endcase

end

endmodule
