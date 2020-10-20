parameter
    SEG_ES = 0, REG_AX = 0, REG_SP = 4, ALU_ADD = 0, ALU_AND = 4,
    SEG_CS = 1, REG_CX = 1, REG_BP = 5, ALU_OR  = 1, ALU_SUB = 5,
    SEG_SS = 2, REG_DX = 2, REG_SI = 6, ALU_ADC = 2, ALU_XOR = 6,
    SEG_DS = 3, REG_BX = 3, REG_DI = 7, ALU_SBB = 3, ALU_CMP = 7,
    REG_AL = 0, REG_AH = 4, ALU_ROL = 0, ALU_SHL = 4,
    REG_CL = 1, REG_CH = 5, ALU_ROR = 1, ALU_SHR = 5,
    REG_DL = 2, REG_DH = 6, ALU_RCL = 2, ALU_SAL = 6,
    REG_BL = 3, REG_BH = 7, ALU_RCR = 3, ALU_SAR = 7;

parameter
    CF = 0, PF = 2, AF = 4,  ZF = 6, SF = 7,
    TF = 8, IF = 9, DF = 10, OF = 11;

parameter
    START  = 0, // Инициализация инструкции
    LOAD   = 1, // Загрузка инструкции и разбор
    MODRM  = 2, // Разбор операндов байта ModRM
    INSTR  = 3, // Выполнение инструкции
    EXTEND = 4, // Расширенный опкод
    INTR   = 5, // Вызов прерывания
    WBACK  = 6, // Запись ModRM в память или регистр
    PUSH   = 7, // Запись в стек
    POP    = 8, // Чтение из стека
    DIV    = 9,  // Деление 8 или 16 бит
    REPF   = 10, // REP[Z|NZ]
    UNDEF  = 11; // Неизвестная инструкция

// ------------------------------ ОТЛАДКА
wire [15:0] dr_ax = r16[REG_AX];
wire [15:0] dr_cx = r16[REG_DI];
wire [15:0] dr_sp = r16[REG_SP];
wire [15:0] dr_se = seg[SEG_CS];
wire        _strob_ = fn == 1;
// ------------------------------

// Инициализация регистров
// ---------------------------------------------------------------------

reg [15:0] r16[8];
reg [15:0] seg[4];
reg [11:0] flags;
reg [15:0] ip;

initial begin

    r16[REG_AX] = 16'h3082;
    r16[REG_CX] = 16'h0003;
    r16[REG_DX] = 16'h1A3F;
    r16[REG_BX] = 16'h0001;
    r16[REG_SP] = 16'h0000;
    r16[REG_BP] = 16'h0000;
    r16[REG_SI] = 16'h0002;
    r16[REG_DI] = 16'h0001;

    seg[SEG_ES] = 16'hF800;
    seg[SEG_CS] = 16'hF800;
    seg[SEG_SS] = 16'h0000;
    seg[SEG_DS] = 16'hB800;

    ip     = 16'h0000;
    flags  = 16'b0000_0000_0010;
    //           ODIT SZ-A -P-C

end

// Первоначальная инициализация
// ---------------------------------------------------------------------

initial begin

    segment_id = SEG_DS;

    bus = 0; modrm   = 0; busen  = 0;
    fn  = 0; i_size  = 0; halt   = 0;
    s1  = 0; i_dir   = 0; s4     = 0;
    wb  = 0; wf      = 0; s5     = 0;
    alu = 0; wb_data = 0; intr   = 0;
    op1 = 0; wb_flag = 0; rep_ft = 0;
    op2 = 0; wb_reg  = 0;
    we  = 0; s2      = 0; s3     = 0;

    irq_accept = 0;
    trace_ff   = 0;
    ip_start   = 0;

    port_address = 0;
    port_out     = 0;
    port_read    = 0;
    port_write   = 0;

end

// Знаковое расширение
wire [15:0] signex = {{8{i_data[7]}}, i_data};

// Состояние процессора в данный момент
// ---------------------------------------------------------------------

reg [ 8:0]  opcode;
reg [15:0]  ip_start;       // Для REP:
reg [ 3:0]  fn;             // Главное состояние процессора
reg [ 3:0]  fnext;          // fn <- fnext после исполения процедуры
reg [ 2:0]  s1;             // Процедура ModRM
reg [ 2:0]  s2;             // Запись в ModRM -> память, регистр
reg [ 2:0]  s3;             // Микрокод
reg [ 2:0]  s4;             // PUSH/POP
reg [ 2:0]  s5;             // DIV
reg         segment_px;     // Наличие префикса в инструкции
reg [ 2:0]  segment_id;     // Номер выбранного сегмента
reg [15:0]  ea;             // Эффективный адрес
reg         bus;            // 0 => CS:IP, 1 => segment_id:ea
reg         busen;          // Использовать ли bus для modrm
reg [ 1:0]  rep;            // REP[0] = NZ|Z; REP[1] = наличие префикса
reg [ 7:0]  modrm;          // Сохраненный байт modrm
reg [15:0]  op1;            // Операнд 1
reg [15:0]  op2;            // Операнд 2
reg         i_dir;          // 0=rm, r; 1=r, rm
reg         i_size;         // 0=8 bit; 1=16 bit
reg         wb;             // Записать в регистры (размер i_size)
reg         wf;             // Запись флагов wb_flag
reg [15:0]  wb_data;        // Какое значение записывать
reg [ 2:0]  wb_reg;         // Номер регистра (0..7)
reg [11:0]  wb_flag;        // Какие флаги писать
reg [ 2:0]  alu;            // Выбор АЛУ режима
reg         halt;           // Процессор остановлен
reg         rep_ft;         // =1 Если надо проверить REPZ/REPNZ
reg         trace_ff;       // FlipFlop для Trace, чтобы исполнялась 1 инструкция
reg         irq_accept;     // Если irq_accept != irq_signal, есть IRQ на входе
reg [ 7:0]  intr;           // Номер вызываемого прерывания для INTR
