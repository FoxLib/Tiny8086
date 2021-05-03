/**
 * Самый часто используемый модуль в процессоре
 *  0 ADD   4 AND   8 ROL   C SHL
 *  1 OR    5 SUB   9 ROR   D SHR
 *  3 ADC   6 XOR   A RCL   E SHL
 *  4 SBB   7 CMP   B RCR   F SAR
 */

module alu
(
    input  wire [3:0]   alu,
    input  wire [15:0]  op1,
    input  wire [15:0]  op2,
    input  wire         bit16,          // 16-битный операнд
    output wire [15:0]  value,
    input  wire [11:0]  flags,
    output reg  [11:0]  flags_out
);

`include "localparam.v"

assign value = result[15:0];

// Некоторые флаги АЛУ
wire zero8  = ~|result[7:0];
wire zero16 = ~|result[15:0];
wire sign8  =   result[7];
wire sign16 =   result[15];
wire parity = ~^result[7:0];

// Специальный случай: переполнение ADD/SUB
wire addof8  = (op1[7]  ^ op2[7]  ^ 1'b1) & (op1[7]  ^ result[7]);
wire addof16 = (op1[15] ^ op2[15] ^ 1'b1) & (op1[15] ^ result[15]);
wire subof8  = (op1[7]  ^ op2[7]        ) & (op1[7]  ^ result[7]);
wire subof16 = (op1[15] ^ op2[15]       ) & (op1[15] ^ result[15]);

reg [16:0] result;

always @* begin

    result    = 0;
    flags_out = 0;

    // Результат вычисления
    case (alu)

        // Арифметика
        alu_add: result = op1 + op2;
        alu_or:  result = op1 | op2;
        alu_adc: result = op1 + op2 + flags[0];
        alu_sbb: result = op1 - op2 - flags[0];
        alu_and: result = op1 & op2;
        alu_sub: result = op1 - op2;
        alu_xor: result = op1 ^ op2;
        alu_cmp: result = op1 - op2;

        // Сдвиги
        alu_rol: result = bit16 ? {op1[14:0], op1[15]}   : {op1[6:0], op1[7]};
        alu_ror: result = bit16 ? {op1[0],    op1[15:1]} : {op1[0],   op1[7:1]};
        alu_rcl: result = bit16 ? {op1[14:0], flags[0]}  : {op1[6:0], flags[0]};
        alu_rcr: result = bit16 ? {flags[0],  op1[15:1]} : {flags[0], op1[7:1]};
        alu_shl, alu_sh2:
                 result = bit16 ? {op1[14:0], 1'b0}      : {op1[6:0], 1'b0};
        alu_shr: result = bit16 ? {1'b0,      op1[15:1]} : {1'b0,     op1[7:1]};
        alu_sar: result = bit16 ? {op1[15],   op1[15:1]} : {op1[7],   op1[7:1]};

    endcase

    // Полученные флаги
    case (alu)

        alu_add,
        alu_adc:

            flags_out = {
                /* 11 OF */ bit16 ? addof16 : addof8,
                /* 10 DF */ flags[10],
                /*  9 IF */ flags[9],
                /*  8 TF */ flags[8],
                /*  7 SF */ bit16 ? sign16 : sign8,
                /*  6 ZF */ bit16 ? zero16 : zero8,
                /*  5  - */ 1'b0,
                /*  4 AF */ op1[3:0] + op2[3:0] + (alu == alu_adc ? flags[0] : 1'b0) >= 5'h10,
                /*  3  - */ 1'b0,
                /*  2 PF */ parity,
                /*  1  - */ 1'b1,
                /*  0 CF */ bit16 ? result[16] : result[8]
            };

        alu_sub,
        alu_sbb,
        alu_cmp:

            flags_out = {
                /* 11 OF */ bit16 ? subof16 : subof8,
                /* 10 DF */ flags[10],
                /*  9 IF */ flags[9],
                /*  8 TF */ flags[8],
                /*  7 SF */ bit16 ? sign16 : sign8,
                /*  6 ZF */ bit16 ? zero16 : zero8,
                /*  5  - */ 1'b0,
                /*  4 AF */ op1[3:0] < op2[3:0] + (alu == alu_sbb ? flags[0] : 1'b0),
                /*  3  - */ 1'b0,
                /*  2 PF */ parity,
                /*  1  - */ 1'b1,
                /*  0 CF */ bit16 ? result[16] : result[8]
            };

        alu_or,
        alu_xor,
        alu_and:

            flags_out = {
                /* 11 OF */ 1'b0,
                /* 10 DF */ flags[10],
                /*  9 IF */ flags[9],
                /*  8 TF */ flags[8],
                /*  7 SF */ bit16 ? sign16 : sign8,
                /*  6 ZF */ bit16 ? zero16 : zero8,
                /*  5  - */ 1'b0,
                /*  4 AF */ result[4], /* Undefined */
                /*  3  - */ 1'b0,
                /*  2 PF */ parity,
                /*  1  - */ 1'b1,
                /*  0 CF */ 1'b0
            };

    endcase

end


endmodule
