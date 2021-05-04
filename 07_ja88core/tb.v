`timescale 10ns / 1ns
module tb;

reg clock;
reg clock_25;
reg clock_50;

always #0.5 clock    = ~clock;
always #1.0 clock_50 = ~clock_50;
always #1.5 clock_25 = ~clock_25;

initial begin clock = 0; clock_25 = 0; clock_50 = 0; #2000 $finish; end
initial begin $dumpfile("tb.vcd"); $dumpvars(0, tb); end

// ---------------------------------------------------------------------
// Контроллер памяти
// ---------------------------------------------------------------------

reg [7:0] memory[1048576];

always @(posedge clock) begin

    bus <= memory[address];
    if (wreq) memory[address] <= data;

end

// ---------------------------------------------------------------------
// Процессор
// ---------------------------------------------------------------------

wire [31:0] address;
reg  [ 7:0] bus;
wire [ 7:0] data;
wire        locked;
wire        wreq;

core88 UnitCPU
(
    .clock      (clock_25),
    .locked     (locked),
    .address    (address),
    .bus        (bus),
    .data       (data),
    .wreq       (wreq)
);

endmodule
