// ---------------------------------------------------------------------
// Списки регистров
// ---------------------------------------------------------------------

// Сегментные регистры
reg [15:0]  seg_cs = 16'hF000;
reg [15:0]  seg_ss = 16'h0000;
reg [15:0]  seg_es = 16'hAFBA;
reg [15:0]  seg_ds = 16'h2377;

// Регистры
reg [15:0]  ax = 16'h1234;
reg [15:0]  bx = 16'h2342;
reg [15:0]  cx = 16'h3344;
reg [15:0]  dx = 16'h6677;
reg [15:0]  sp = 16'h5432;
reg [15:0]  bp = 16'h5678;
reg [15:0]  si = 16'h9ABD;
reg [15:0]  di = 16'hEF01;
reg [15:0]  ip = 0;
reg [11:0]  flags = 0;

reg [15:0]  seg_ea  = 0;
reg [15:0]  ea      = 0;

// Выбранная шина адреса (sel=1) seg:ea (sel=0) cs:ip
reg         sel     = 0;
reg         sel_seg = 0;
reg [ 1:0]  sel_rep = 0;

// ---------------------------------------------------------------------
// Состояние процессора
// ---------------------------------------------------------------------

reg [2:0]   main    = 0;
reg [3:0]   tstate  = 0;
reg [3:0]   estate  = 0;
reg [7:0]   opcode  = 0;
reg [7:0]   modrm   = 0;
reg         isize   = 0;    // 8|16
reg         idir    = 0;    // rm,r | r,rm
reg [ 2:0]  regn    = 0;    // regv = register[regn]
reg [ 3:0]  alumode = 0;
reg [15:0]  op1     = 0;
reg [15:0]  op2     = 0;
reg [15:0]  wb      = 0;    // Для записи в reg/rm

// ---------------------------------------------------------------------
// Константы и initial
// ---------------------------------------------------------------------

localparam
    CF = 0, PF = 2, AF = 4,  ZF = 6, SF = 7,
    TF = 8, IF = 9, DF = 10, OF = 11;

localparam

    PREPARE     = 0,        // Эта подготовки инструкции к исполнению
    MAIN        = 1,        // Обработка микрокода
    FETCHEA     = 2,        // Считывание ModRM/EA
    SETEA       = 3,         // Запись в память или регистр
    PUSH        = 4,
    POP         = 5,
    INTERRUPT   = 6,
    IMMEDIATE   = 7;

initial data = 8'hFF;
initial wreq = 0;

// ---------------------------------------------------------------------
// Предвычисления
// ---------------------------------------------------------------------

// Выбор регистра
wire [15:0] regv =
    regn == 0 ? (isize ? ax : ax[ 7:0]) :
    regn == 1 ? (isize ? cx : cx[ 7:0]) :
    regn == 2 ? (isize ? dx : dx[ 7:0]) :
    regn == 3 ? (isize ? bx : bx[ 7:0]) :
    regn == 4 ? (isize ? sp : ax[15:8]) :
    regn == 5 ? (isize ? bp : cx[15:8]) :
    regn == 6 ? (isize ? si : dx[15:8]) :
                (isize ? di : bx[15:8]);

// Вычисление условий
wire [7:0] branches = {

    (flags[SF] ^ flags[OF]) | flags[ZF], // 7: (ZF=1) OR (SF!=OF)
    (flags[SF] ^ flags[OF]),             // 6: SF!=OF
     flags[PF], flags[SF],               // 5: PF; 4: SF
     flags[CF] | flags[OF],              // 3: CF != OF
     flags[ZF], flags[CF], flags[OF]     // 2: OF; 1: CF; 0: ZF
};

// ---------------------------------------------------------------------
// Модули
// ---------------------------------------------------------------------

wire [15:0] result;
wire [15:0] daa_r;
wire [11:0] flags_o;
wire [11:0] flags_d;

alu UnitALU
(
    // Входящие данные
    .isize      (isize),
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

