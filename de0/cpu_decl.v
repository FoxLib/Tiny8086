parameter
    SEG_ES = 0, REG_AX = 0, REG_SP = 4, ALU_ADD = 0, ALU_AND = 4,
    SEG_CS = 1, REG_CX = 1, REG_BP = 5, ALU_OR  = 1, ALU_SUB = 5,
    SEG_SS = 2, REG_DX = 2, REG_SI = 6, ALU_ADC = 2, ALU_XOR = 6,
    SEG_DS = 3, REG_BX = 3, REG_DI = 7, ALU_SBB = 3, ALU_CMP = 7;

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
    POP    = 8; // Чтение из стека

// Инициализация регистров
// ---------------------------------------------------------------------

reg [15:0] r16[8];
reg [15:0] seg[6];
reg [11:0] flags;
reg [15:0] ip;

initial begin

    r16[REG_AX] = 16'h3452;
    r16[REG_CX] = 16'hFFFF;
    r16[REG_DX] = 16'h0000;
    r16[REG_BX] = 16'h0001;
    r16[REG_SP] = 16'h0000;
    r16[REG_BP] = 16'h0000;
    r16[REG_SI] = 16'h0001;
    r16[REG_DI] = 16'h0000;

    seg[SEG_ES] = 16'h0000;
    seg[SEG_CS] = 16'h0000;
    seg[SEG_SS] = 16'h0000;
    seg[SEG_DS] = 16'h0000;

    ip     = 16'h0000;
    flags  = 16'b0000_0000_0010;
    //           ODIT SZ-A -P-C

end

// Первоначальная инициализация
// ---------------------------------------------------------------------

initial begin

    segment_id = SEG_DS;

    bus = 0; modrm   = 0; busen = 0;
    fn  = 0; i_size  = 0;
    s1  = 0; i_dir   = 0;
    wb  = 0; wf      = 0;
    alu = 0; wb_data = 0;
    op1 = 0; wb_flag = 0;
    op2 = 0; wb_reg  = 0;
    we  = 0;

end

// Состояние процессора в данный момент
// ---------------------------------------------------------------------

reg [ 8:0]  opcode;
reg [ 3:0]  fn;                 // Главное состояние процессора
reg [ 3:0]  fnext;              // fn <- fnext после исполения процедуры
reg [ 2:0]  s1;                 // Процедура ModRM
reg [ 2:0]  s2;                 // Запись в ModRM -> память, регистр
reg [ 2:0]  s3;                 // Микрокод
reg         segment_px;         // Наличие префикса в инструкции
reg [ 2:0]  segment_id;         // Номер выбранного сегмента
reg [15:0]  ea;                 // Эффективный адрес
reg         bus;                // 0 => CS:IP, 1 => segment_id:ea
reg         busen;              // Использовать ли bus для modrm
reg [ 1:0]  rep;                // REP[0] = NZ|Z; REP[1] = наличие префикса
reg [ 7:0]  modrm;              // Сохраненный байт modrm
reg [15:0]  op1;                // Операнд 1
reg [15:0]  op2;                // Операнд 2
reg         i_dir;              // 0=rm, r; 1=r, rm
reg         i_size;             // 0=8 bit; 1=16 bit
reg         wb;                 // Записать в регистры (размер i_size)
reg         wf;                 // Запись флагов wb_flag
reg [15:0]  wb_data;            // Какое значение записывать
reg [ 2:0]  wb_reg;             // Номер регистра (0..7)
reg [11:0]  wb_flag;            // Какие флаги писать
reg [ 2:0]  alu;                // Выбор АЛУ режима

