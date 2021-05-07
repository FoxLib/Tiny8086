module de0(

    // Reset
    input              RESET_N,

    // Clocks
    input              CLOCK_50,
    input              CLOCK2_50,
    input              CLOCK3_50,
    inout              CLOCK4_50,

    // DRAM
    output             DRAM_CKE,
    output             DRAM_CLK,
    output      [1:0]  DRAM_BA,
    output      [12:0] DRAM_ADDR,
    inout       [15:0] DRAM_DQ,
    output             DRAM_CAS_N,
    output             DRAM_RAS_N,
    output             DRAM_WE_N,
    output             DRAM_CS_N,
    output             DRAM_LDQM,
    output             DRAM_UDQM,

    // GPIO
    inout       [35:0] GPIO_0,
    inout       [35:0] GPIO_1,

    // 7-Segment LED
    output      [6:0]  HEX0,
    output      [6:0]  HEX1,
    output      [6:0]  HEX2,
    output      [6:0]  HEX3,
    output      [6:0]  HEX4,
    output      [6:0]  HEX5,

    // Keys
    input       [3:0]  KEY,

    // LED
    output      [9:0]  LEDR,

    // PS/2
    inout              PS2_CLK,
    inout              PS2_DAT,
    inout              PS2_CLK2,
    inout              PS2_DAT2,

    // SD-Card
    output             SD_CLK,
    inout              SD_CMD,
    inout       [3:0]  SD_DATA,

    // Switch
    input       [9:0]  SW,

    // VGA
    output      [3:0]  VGA_R,
    output      [3:0]  VGA_G,
    output      [3:0]  VGA_B,
    output             VGA_HS,
    output             VGA_VS
);

// Z-state
assign DRAM_DQ = 16'hzzzz;
assign GPIO_0  = 36'hzzzzzzzz;
assign GPIO_1  = 36'hzzzzzzzz;

// LED OFF
assign HEX0 = 7'b1111111;
assign HEX1 = 7'b1111111;
assign HEX2 = 7'b1111111;
assign HEX3 = 7'b1111111;
assign HEX4 = 7'b1111111;
assign HEX5 = 7'b1111111;

// ---------------------------------------------------------------------
// Генерация частот
// ---------------------------------------------------------------------

wire locked;
wire clock_25;
wire clock_100;

de0pll UnitPLL
(
    .clkin     (CLOCK_50),
    .m25       (clock_25),
    .m100      (clock_100),
    .locked    (locked)
);

// ---------------------------------------------------------------------
// Видеоадаптер
// ---------------------------------------------------------------------

wire [12:0] cga_address;
wire [ 7:0] cga_data;
reg  [10:0] cga_cursor;

cga CGA
(
    .clock_25   (clock_25),
    // Интерфейс
    .R (VGA_R), .HS (VGA_HS),
    .G (VGA_G), .VS (VGA_VS),
    .B (VGA_B),
    // Память
    .address    (cga_address),
    .data       (cga_data),
    .cursor     (cga_cursor),
);

// Контроллер памяти
// ---------------------------------------------------------------------

// Процессор
wire [19:0] address;
wire [ 7:0] o_data;
wire        we;

// Входящие данные
wire [ 7:0] q_cgamem;
wire [ 7:0] q_memory;
wire [ 7:0] q_bios;
reg  [ 7:0] i_data;

reg we_cgamem = 0;
reg we_memory = 0;

// 256kb
memory MEMORY
(
    .clock      (clock_100),
    .address_a  (address[17:0]),
    .data_a     (o_data),
    .wren_a     (we_memory),
    .q_a        (q_memory)
);

// 8kb
cgamem CGAMEM
(
    .clock      (clock_100),
    .address_a  (cga_address),
    .q_a        (cga_data),
    .address_b  (address[12:0]),
    .data_b     (o_data),
    .wren_b     (we_cgamem),
    .q_b        (q_cgamem)
);

// 8kb
bios BIOS
(
    .clock      (clock_100),
    .address_a  (address[12:0]),
    .q_a        (q_bios)
);

// Маршрутизация
always @* begin

    i_data    = 8'hFF;
    we_cgamem = 0;
    we_memory = 0;

    casex (address)

        // 00000-3ffff 256k Общая память
        20'b00xx_xxxx_xxxx_xxxx_xxxx: begin i_data = q_memory; we_memory = we; end

        // b8000-b9fff 8k CGA
        20'b1011_100x_xxxx_xxxx_xxxx: begin i_data = q_cgamem; we_cgamem = we; end

        // f0000-f1fff 8k BIOS
        20'b1111_000x_xxxx_xxxx_xxxx: begin i_data = q_bios; end

    endcase

end

// ---------------------------------------------------------------------
// Ядро процессора
// ---------------------------------------------------------------------

core88 UnitCore88
(
    .clock      (clock_25),
    .resetn     (locked),
    .locked     (locked),
    .address    (address),
    .bus        (i_data),
    .data       (o_data),
    .wreq       (we)
);


endmodule

`include "../cga.v"
`include "../core88.v"
`include "../alu.v"
