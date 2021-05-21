// ---------------------------------------------------------------------
// Списки регистров
// ---------------------------------------------------------------------

// Сегментные регистры
reg [15:0]  seg_cs = 16'hF000;
reg [15:0]  seg_ss = 16'h0000;
reg [15:0]  seg_es = 16'h0000;
reg [15:0]  seg_ds = 16'h0000;
reg [15:0]  seg_fs = 16'h0000;
reg [15:0]  seg_gs = 16'h0000;

// Регистры
reg [31:0]  eax = 32'h4321_121B;
reg [31:0]  ebx = 32'hefd0_0000;
reg [31:0]  ecx = 32'ha1ac_0005;
reg [31:0]  edx = 32'h0b21_8001;
reg [31:0]  esp = 32'haaa3_5432;
reg [31:0]  ebp = 32'ha940_5678;
reg [31:0]  esi = 32'ha580_0002;
reg [31:0]  edi = 32'ha670_0004;

// Системные
reg [15:0]  ip      = 0;
reg [15:0]  ipstart = 0;
reg [15:0]  seg_ea  = 0;
reg [31:0]  ea      = 0;

//                        ODIT SZ A P C
reg [11:0]  flags   = 12'b0000_00000010;

// Выбранная шина адреса (sel=1) seg:ea (sel=0) cs:ip
reg         sel     = 0;
reg         sel_seg = 0;
reg [ 1:0]  sel_rep = 0;

// ---------------------------------------------------------------------
// Состояние процессора
// ---------------------------------------------------------------------

reg [3:0]   mode    = 0;
reg [3:0]   tstate  = 0;
reg [4:0]   estate  = 0;
reg [8:0]   opcode  = 0;
reg [7:0]   modrm   = 0;
reg         skip_op = 0;    // Не считывать операнды
reg         stack32 = 0;    // 16/32
reg         isize   = 0;    // 8/16
reg         opsize  = 0;    // 16/32
reg         opsizet = 0;
reg         adsize  = 0;    // 16/32
reg         idir    = 0;    // rm,r | r,rm
reg [ 2:0]  regn    = 0;    // regv = register[regn]
reg [ 2:0]  alumode = 0;
reg [31:0]  op1     = 0;
reg [31:0]  op2     = 0;
reg [31:0]  wb      = 0;    // Для записи в reg/rm
reg [15:0]  tmp16   = 0;
reg         is_intr = 0;
reg [63:0]  rdtsc   = 0;

// Модуль деления op1 / op2 -> divres | divrem
reg [63:0]  diva    = 0;
reg [63:0]  divb    = 0;
reg [ 6:0]  divcnt  = 0;
reg [63:0]  divrem  = 0;
reg [63:0]  divres  = 0;
reg         signa;
reg         signb;

// ---------------------------------------------------------------------
// Константы и initial
// ---------------------------------------------------------------------

localparam
    CF = 0, PF = 2, AF = 4,  ZF = 6, SF = 7,
    TF = 8, IF = 9, DF = 10, OF = 11;

localparam

    PREPARE     = 0,    // Эта подготовки инструкции к исполнению
    MAIN        = 1,    // Обработка микрокода
    FETCHEA     = 2,    // Считывание ModRM/EA
    SETEA       = 3,    // Запись в память или регистр
    PUSH        = 4,    // Запись в стек
    POP         = 5,    // Извлечь из стека
    INTERRUPT   = 6,    // Вызов прерывания
    LOADSEG     = 7,    // Загрузка сегмента
    IMMEDIATE   = 8,    // Непосредственное значение
    SHIFT       = 9,    // Сдвиги
    DIVIDE      = 10,   // Деление 8/16/32 битного
    EXTENDED0   = 11,
    EXTENDED    = 12;   // Расширенный опкод

initial begin data = 8'hFF; wreq = 0; port_w = 0; port_o = 0; port_clk = 0; port = 0; intr_latch = 0; end

// ---------------------------------------------------------------------
// Предвычисления
// ---------------------------------------------------------------------

// Выбор регистра
wire [31:0] regv =
    regn == 0 ? (isize ? (opsize ? eax : eax[15:0]) : eax[ 7:0]) :
    regn == 1 ? (isize ? (opsize ? ecx : ecx[15:0]) : ecx[ 7:0]) :
    regn == 2 ? (isize ? (opsize ? edx : edx[15:0]) : edx[ 7:0]) :
    regn == 3 ? (isize ? (opsize ? ebx : ebx[15:0]) : ebx[ 7:0]) :
    regn == 4 ? (isize ? (opsize ? esp : esp[15:0]) : eax[15:8]) :
    regn == 5 ? (isize ? (opsize ? ebp : ebp[15:0]) : ecx[15:8]) :
    regn == 6 ? (isize ? (opsize ? esi : esi[15:0]) : edx[15:8]) :
                (isize ? (opsize ? edi : edi[15:0]) : ebx[15:8]);

// Вычисление условий
wire [7:0] branches = {

    (flags[SF] ^ flags[OF]) | flags[ZF], // 7: (ZF=1) OR (SF!=OF)
    (flags[SF] ^ flags[OF]),             // 6: SF!=OF
     flags[PF],                          // 5: PF
     flags[SF],                          // 4: SF
     flags[CF] | flags[ZF],              // 3: CF or ZF
     flags[ZF],                          // 2: ZF
     flags[CF],                          // 1: CF
     flags[OF]                           // 0: OF
};

// Модуль умножения
wire [63:0] mult  = op1 * op2;
wire        signd = signa ^ signb;

// ---------------------------------------------------------------------
// Модули
// ---------------------------------------------------------------------

wire [31:0] result;
wire [15:0] daa_r;
wire [11:0] flags_o;
wire [11:0] flags_d;

alu UnitALU
(
    // Входящие данные
    .isize      (isize),
    .opsize     (opsize),
    .alumode    (alumode),
    .op1        (op1),
    .op2        (op2),
    .flags      (flags),

    // Исходящие данные
    .result     (result),
    .flags_o    (flags_o),
    .daa_r      (daa_r),
    .flags_d    (flags_d)
);
