`timescale 10ns / 1ns
module tb;

reg clock;
reg clock_50;
reg clock_25;

always #0.5 clock    = ~clock;
always #1.0 clock_50 = ~clock_50;
always #1.5 clock_25 = ~clock_25;

initial begin clock = 0; clock_25 = 0; clock_50 = 0; #5000 $finish; end
initial begin $dumpfile("tb.vcd"); $dumpvars(0, tb); end

// ---------------------------------------------------------------------
// Контроллер внутрисхемной памяти
// ---------------------------------------------------------------------

reg [7:0] memory[1048576];

initial $readmemh("bios.hex", memory, 20'hF0000);
initial $readmemh("mem.hex",  memory, 20'h00000);

always @(posedge clock) begin

    bus <= memory[address];
    if (wreq) memory[address] <= data;

end

// ---------------------------------------------------------------------
// Отладка
// ---------------------------------------------------------------------

initial begin

    #20.0 ps2_hit = 1;
    #2    ps2_hit = 0;
    #500  ps2_hit = 1;
    #2    ps2_hit = 0;

end

// ---------------------------------------------------------------------
// Процессор
// ---------------------------------------------------------------------

wire [19:0] address;
reg  [ 7:0] bus;
wire [ 7:0] data;
wire        locked;
wire        wreq;

wire        port_clk;
wire [15:0] port;
wire [ 7:0] port_i;
wire [ 7:0] port_o;
wire        port_w;

wire        intr;
wire        intr_latch;
wire [ 7:0] irq;

reg  [ 7:0] ps2_data = 8'h01;
reg         ps2_hit  = 0;

wire [10:0] vga_cursor;

wire [1:0]  sd_cmd;
wire [7:0]  sd_din;
wire [7:0]  sd_out;
wire        sd_signal;
wire        sd_busy;
wire        sd_timeout;

wire [31:0] dac_out;
wire [ 7:0] dac_address;
wire        dac_we;

core88 UnitCPU
(
    .clock      (clock_25),
    .resetn     (1'b1),
    .locked     (1'b1),

    // Данные
    .address    (address),
    .bus        (bus),
    .data       (data),
    .wreq       (wreq),

    // Порты
    .port_clk   (port_clk),
    .port       (port),
    .port_i     (port_i),
    .port_o     (port_o),
    .port_w     (port_w),

    // Прерывания
    .intr       (intr),
    .irq        (irq),
    .intr_latch (intr_latch)
);

portctl PortCtlUnit
(
    .resetn     (1'b1),
    .clock      (clock_25),
    .clock50    (clock_50),
    .port_clk   (port_clk),
    .port       (port),
    .port_i     (port_i),
    .port_o     (port_o),
    .port_w     (port_w),

    // Устройства
    .vga_cursor (vga_cursor),
    .ps2_data   (ps2_data),
    .ps2_hit    (ps2_hit),
    .dac_out    (dac_out),
    .dac_address(dac_address),
    .dac_we     (dac_we),

    // SD-карта
    .sd_signal  (sd_signal),   // In   =1 Сообщение отослано на spi
    .sd_cmd     (sd_cmd),      // In      Команда
    .sd_din     (sd_din),      // Out     Принятое сообщение от карты
    .sd_out     (sd_out),      // In      Сообщение на отправку к карте
    .sd_busy    (sd_busy),     // Out  =1 Занято
    .sd_timeout (sd_timeout),  // Out  =1 Таймаут

    // Прерывания
    .intr       (intr),
    .irq        (irq),
    .intr_latch (intr_latch)
);

// ---------------------------------------------------------------------
// Модуль SD
// ---------------------------------------------------------------------

assign SD_DATA[0] = 1'bZ;

wire [3:0]  SD_DATA;

sd UnitSD
(
    // 50 Mhz
    .clock50    (clock_50),

    // Физический интерфейс
    .SPI_CS     (SD_DATA[3]),   // Выбор чипа
    .SPI_SCLK   (SD_CLK),       // Тактовая частота
    .SPI_MISO   (SD_DATA[0]),   // Входящие данные
    .SPI_MOSI   (SD_CMD),       // Исходящие

    // Интерфейс
    .sd_signal  (sd_signal),   // In   =1 Сообщение отослано на spi
    .sd_cmd     (sd_cmd),      // In      Команда
    .sd_din     (sd_din),      // Out     Принятое сообщение от карты
    .sd_out     (sd_out),      // In      Сообщение на отправку к карте
    .sd_busy    (sd_busy),     // Out  =1 Занято
    .sd_timeout (sd_timeout)   // Out  =1 Таймаут
);

endmodule
