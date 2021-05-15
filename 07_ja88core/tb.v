`timescale 10ns / 1ns
module tb;

reg clock;
reg clock_50;
reg clock_25;

always #0.5 clock    = ~clock;
always #1.0 clock_50 = ~clock_50;
always #1.5 clock_25 = ~clock_25;

initial begin clock = 0; clock_25 = 0; clock_50 = 0; #2000 $finish; end
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
// Процессор
// ---------------------------------------------------------------------

wire [19:0] address;
reg  [ 7:0] bus;
wire [ 7:0] data;
wire        locked;
wire        wreq;

wire        port_clk;
wire [15:0] port;
reg  [ 7:0] port_i = 8'hFF;
wire [ 7:0] port_o;
wire        port_w;

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
    .port_w     (port_w)
);

endmodule
