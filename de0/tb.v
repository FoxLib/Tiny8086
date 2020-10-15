`timescale 10ns / 1ns

module tb;

// ---------------------------------------------------------------------
reg clock;
reg clock25;

always #0.5 clock   = ~clock;
always #1.5 clock25 = ~clock25;

initial begin clock = 0; clock25 = 0; #2000 $finish; end
initial begin $dumpfile("tb.vcd"); $dumpvars(0, tb); end
// ---------------------------------------------------------------------

reg  [ 7:0] ram[1048576];
wire [19:0] address;
reg  [ 7:0] i_data;
wire [ 7:0] o_data;
wire        we;

initial $readmemh("program.hex", ram, 16'h0000);

/* Формируется логика чтения и записи в память */
always @(posedge clock) begin

    i_data <= ram[ address ];
    if (we) ram[ address ] <= o_data;

end
// ---------------------------------------------------------------------

cpu CPU86
(
    .clock      (clock25),
    .address    (address),
    .i_data     (i_data),
    .o_data     (o_data),
    .we         (we)
);

endmodule
