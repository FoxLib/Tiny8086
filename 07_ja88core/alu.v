module alu
(
    // Входящие данные
    input   wire        isize,
    input   wire [ 3:0] alumode,
    input   wire [15:0] op1,
    input   wire [15:0] op2,
    input   wire [11:0] flags,

    // Исходящие данные
    output  wire [15:0] result,
    output  reg  [11:0] flags_o,
    output  reg  [15:0] daa_r,
    output  reg  [11:0] flags_d
);

assign result = isize ? res[15:0] : res[7:0];

reg [16:0] res;

wire parity  = ~^res[7:0];
wire zerof   = ~(isize ? |res[15:0] : |res[7:0]);
wire carryf  = res[isize ? 16 : 8];
wire signf   = res[isize ? 15 : 7];
wire auxf    = op1[4]^op2[4]^res[4];

// Самая хитрая логика из всего тут
wire add8o   = (op1[ 7] ^ op2[ 7] ^ 1) & (op1[ 7] ^ res[ 7]);
wire sub8o   = (op1[ 7] ^ op2[ 7] ^ 0) & (op1[ 7] ^ res[ 7]);
wire add16o  = (op1[15] ^ op2[15] ^ 1) & (op1[15] ^ res[15]);
wire sub16o  = (op1[15] ^ op2[15] ^ 0) & (op1[15] ^ res[15]);

reg       daa_a;
reg       daa_c;
reg       daa_x;
reg [7:0] daa_i;


// Общие АЛУ
always @* begin

    case (alumode)

        /* ADD */ 0: res = op1 + op2;
        /* OR  */ 1: res = op1 | op2;
        /* ADC */ 2: res = op1 + op2 + flags[0];
        /* SBB */ 3: res = op1 - op2 - flags[0];
        /* AND */ 4: res = op1 & op2;
        /* SUB */ 5,
        /* CMP */ 7: res = op1 - op2;
        /* XOR */ 6: res = op1 ^ op2;

    endcase

    case (alumode)

        // ADD | ADC
        0, 2: flags_o = {

            /* O */ (isize ? add16o : add8o),
            /* D */ flags[10],
            /* I */ flags[9],
            /* T */ flags[8],
            /* S */ signf,
            /* Z */ zerof,
            /* 0 */ 1'b0,
            /* A */ auxf,
            /* 0 */ 1'b0,
            /* P */ parity,
            /* 1 */ 1'b1,
            /* C */ carryf
        };

        // SBB | SUB | CMP
        3, 5, 7: flags_o = {

            /* O */ (isize ? sub16o : sub8o),
            /* D */ flags[10],
            /* I */ flags[9],
            /* T */ flags[8],
            /* S */ signf,
            /* Z */ zerof,
            /* 0 */ 1'b0,
            /* A */ auxf,
            /* 0 */ 1'b0,
            /* P */ parity,
            /* 1 */ 1'b1,
            /* C */ carryf
        };

        // OR, AND, XOR одинаковые флаги
        1, 4, 6: flags_o = {

            /* O */ 1'b0,
            /* D */ flags[10],
            /* I */ flags[9],
            /* T */ flags[8],
            /* S */ signf,
            /* Z */ zerof,
            /* 0 */ 1'b0,
            /* A */ 1'b0,
            /* 0 */ 1'b0,
            /* P */ parity,
            /* 1 */ 1'b1,
            /* C */ 1'b0
        };

    endcase


end

// Десятичная коррекция
always @* begin

    daa_r   = op1[7:0];
    flags_d = flags;

    case (alumode)

        // DAA
        0: begin

            daa_c = flags[0];
            daa_a = flags[4];
            daa_i = op1[7:0];

            // Младший ниббл
            if (op1[3:0] > 9 || flags[4]) begin
                daa_i = op1[7:0] + 6;
                daa_c = 1;
                daa_a = 1;
            end

            daa_r = daa_i;
            daa_x = daa_c;

            // Старший ниббл
            if (daa_c || daa_i > 8'h9F) begin
                daa_r = daa_i + 8'h60;
                daa_x = 1'b1;
            end

            flags_d[7] =   daa_r[7];        // S
            flags_d[6] = ~|daa_r[7:0];      // Z
            flags_d[4] =   daa_a;           // A
            flags_d[2] = ~^daa_r[7:0];      // P
            flags_d[0] =   daa_x;           // C

        end

    endcase

end

endmodule
