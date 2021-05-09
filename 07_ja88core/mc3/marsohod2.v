module marsohod2
(
    input   wire        clk,
    output  wire [3:0]  led,
    input   wire [1:0]  keys,
    output  wire        adc_clock_20mhz,
    input   wire [7:0]  adc_input,
    output  wire        sdram_clock,
    output  wire [11:0] sdram_addr,
    output  wire [1:0]  sdram_bank,
    inout   wire [15:0] sdram_dq,
    output  wire        sdram_ldqm,
    output  wire        sdram_udqm,
    output  wire        sdram_ras,
    output  wire        sdram_cas,
    output  wire        sdram_we,
    output  wire [4:0]  vga_r,
    output  wire [5:0]  vga_g,
    output  wire [4:0]  vga_b,
    output  wire        vga_hs,
    output  wire        vga_vs,
    input   wire        ftdi_rx,
    output  wire        ftdi_tx
);

// Генерация частот
wire locked;
wire clock_25;
wire clock_100;

pll unit_pll
(
    .clk       (clk),
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
    .R (vga_r[4:1]), 
    .G (vga_g[5:2]), 
    .B (vga_b[4:1]),
    .HS (vga_hs),
    .VS (vga_vs),
    
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
`include "../alu.v"
`include "../core88.v"
