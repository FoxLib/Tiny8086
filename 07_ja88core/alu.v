module alu
(
    // Входящие данные
    input   wire        isize,
    input   wire        opsize,
    input   wire [ 2:0] alumode,
    input   wire [31:0] op1,
    input   wire [31:0] op2,
    input   wire [11:0] flags,

    // Исходящие данные
    output  wire [31:0] result,
    output  reg  [11:0] flags_o,
    output  reg  [15:0] daa_r,
    output  reg  [11:0] flags_d
);

assign result = isize ? (opsize ? res[31:0] : res[15:0]) : res[7:0];

reg [32:0] res;

// Верхний бит 7, 15 или 31
wire [3:0] signx = isize ? (opsize ? 31 : 15) : 7;

wire parity  = ~^res[7:0];
wire zerof   = isize ? (opsize ? ~|res : ~|res[15:0]) : ~|res[7:0];
wire carryf  = res[signx + 1];
wire signf   = res[signx];
wire auxf    = op1[4]^op2[4]^res[4];

// Самая хитрая логика из всего тут
wire add_o   = (op1[isize] ^ op2[isize] ^ 1) & (op1[isize] ^ res[isize]);
wire sub_o   = (op1[isize] ^ op2[isize] ^ 0) & (op1[isize] ^ res[isize]);

// Десятичная коррекция
reg       daa_a;
reg       daa_c;
reg       daa_x;
reg [8:0] daa_i;
reg [7:0] daa_h;

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

            /* O */ add_o,
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

            /* O */ sub_o,
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

        // DAA, DAS
        0, 1: begin

            daa_c = flags[0];
            daa_a = flags[4];
            daa_i = op1[7:0];

            // Младший ниббл
            if (op1[3:0] > 9 || flags[4]) begin
                daa_i = alumode[0] ? op1[7:0]-6 : op1[7:0]+6;
                daa_c = daa_i[8];
                daa_a = 1;
            end

            daa_r = daa_i[7:0];
            daa_x = daa_c;

            // Старший ниббл
            if (daa_c || daa_i[7:0] > 8'h9F) begin
                daa_r = alumode[0] ? daa_i[7:0]-8'h60 : daa_i[7:0]+8'h60;
                daa_x = 1;
            end

            flags_d[7] =   daa_r[7];        // S
            flags_d[6] = ~|daa_r[7:0];      // Z
            flags_d[4] =   daa_a;           // A
            flags_d[2] = ~^daa_r[7:0];      // P
            flags_d[0] =   daa_x;           // C

        end

        // AAA, AAS
        2, 3: begin

            daa_i = op1[ 7:0];
            daa_r = op1[15:0];

            if (flags[4] || op1[3:0] > 9) begin

                daa_i = alumode[0] ? op1[ 7:0] - 6 : op1[ 7:0] + 6;
                daa_h = alumode[0] ? op1[15:8] - 1 : op1[15:8] + 1;
                daa_r = {daa_h, 4'h0, daa_i[3:0]};

                flags_d[4] = 1; // AF=1
                flags_d[0] = 1; // CF=1

            end
            else begin flags_d[4] = 0; flags_d[0] = 0; end

        end

    endcase

end

endmodule
