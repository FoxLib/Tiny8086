`include "localparam.v"

wire [15:0] __debug = r[reg_dx];

// ---------------------------------------------------------------------
initial begin

    out       = 8'h00;
    wren      = 1'b0;

    s[seg_es] = 16'h1122;
    s[seg_cs] = 16'h0000;
    s[seg_ss] = 16'hF123;
    s[seg_ds] = 16'h0000;

    r[reg_ax] = 16'h87A3; r[reg_sp] = 16'hEFAE;
    r[reg_cx] = 16'h8081; r[reg_bp] = 16'hBABA;
    r[reg_dx] = 16'h6677; r[reg_si] = 16'hBEBE;
    r[reg_bx] = 16'hAFFA; r[reg_di] = 16'hCACA;

end

// ---------------------------------------------------------------------
reg [ 2:0]  sub     = 0;        // Текущая исполняемая процедура
reg [ 2:0]  subret  = 0;        // RETURN для процедуры
reg [ 2:0]  fn      = 0;        // Субфункция #1
reg [ 2:0]  fn2     = 0;        // Субфункция #2
reg [ 7:0]  opcode  = 0;
reg         swi     = 1'b0;     // =1 Используется эффективный [seg:eff]
reg         override = 1'b0;
reg        _override = 1'b0;
reg [ 1:0]  rep     = 0;        // Бит 1: Есть ли REP: префикс
reg [ 1:0] _rep     = 0;        // Бит 0: 0=RepNZ, 1=RepZ
reg [ 3:0]  alu     = 16'h0;    // Номер АЛУ-операции
reg [15:0]  op1     = 16'h0;    // Левый операнд
reg [15:0]  op2     = 16'h0;    // Правый операнд
reg         bit16   = 0;        // Используются 16-битные операнды
reg         dir     = 0;        // 0=r/m,reg | 1=reg,r/m
reg [ 7:0]  modrm   = 8'h00;    // Сохраненный байт ModRM
reg [15:0]  wb      = 16'h0000; // Значение для обратной записи в modrm

// Эффективный адрес
reg [15:0]  seg = 0;
reg [15:0] _seg = 16'h0000;
reg [15:0]  eff = 0;
// ---------------------------------------------------------------------
reg [15:0]  r[8];               // Регистры общего назначения
reg [15:0]  s[4];               // Сегменты es: cs: ss: es:
reg [15:0]  ip    = 16'h8000;   // "PostBios" загрузка
reg [11:0]  flags = 12'b0000_0000_0001;
                    //  ODIT SZ A  P C
// ---------------------------------------------------------------------
wire [2:0]  data53  =   data[5:3];
wire [2:0]  data20  =   data[2:0];
wire [15:0] rdata43 = r[data[4:3]];
wire [15:0] rdata10 = r[data[1:0]];
wire [2:0]  opc20   = opcode[2:0];
wire [2:0]  opc43   = opcode[4:3];
// ---------------------------------------------------------------------
wire [7:0]  condition =
{
    (flags[flag_s] ^ flags[flag_o]) | (flags[flag_z]),  // JLE
    (flags[flag_s] ^ flags[flag_o]),                    // 6 JL
     flags[flag_p],                                     // 5 JP
     flags[flag_s],                                     // 4 JS
    (flags[flag_c] | flags[flag_z]),                    // 3 JBE
     flags[flag_z],                                     // 2 JZ
     flags[flag_c],                                     // 1 JC
     flags[flag_o]                                      // 0 JO
};
// ---------------------------------------------------------------------
assign      address = swi ? {seg, 4'h0} + eff : {s[seg_cs], 4'h0} + ip;
// ---------------------------------------------------------------------

// ---------------------------------------------------------------------
// Объявление арифметико-логического устройства
// ---------------------------------------------------------------------

wire [15:0] result;
wire [11:0] flags_out;

alu ArithLogicUnit
(
    .alu    (alu),
    .op1    (op1),
    .op2    (op2),
    .flags  (flags),
    .bit16  (bit16),
    .value  (result),
    .flags_out (flags_out)
);
