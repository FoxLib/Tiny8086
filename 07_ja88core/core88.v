module core88
(
    input   wire        clock,
    input   wire        locked,
    output  wire [31:0] address,
    input   wire [ 7:0] bus,
    output  reg  [ 7:0] data,
    output  reg         wreq
);

endmodule
