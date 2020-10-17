`timescale 10ns / 1ns

module tb;

// ---------------------------------------------------------------------
reg clock;
reg clock25;
reg clock50;

always #0.5 clock   = ~clock;
always #1.0 clock50 = ~clock50;
always #1.5 clock25 = ~clock25;

initial begin clock = 0; clock25 = 0; clock50 = 0; #2000 $finish; end
initial begin

    #10.0 kb_data = 8'h3F;
    #10.0 kb_hit = 1;
    #2.0  kb_hit = 0;

end
initial begin $dumpfile("tb.vcd"); $dumpvars(0, tb); end
// ---------------------------------------------------------------------

reg  [ 7:0] ram[1048576];
wire [19:0] address;
reg  [ 7:0] i_data;
wire [ 7:0] o_data;
wire        we;

initial $readmemh("program.hex", ram, 20'hF8000);

/* Формируется логика чтения и записи в память */
always @(posedge clock) begin

    i_data <= ram[ address ];
    if (we) ram[ address ] <= o_data;

end

// ---------------------------------------------------------------------
// Контроллер портов-ввода вывода
// ---------------------------------------------------------------------

wire [15:0] port_address;
wire [ 7:0] port_in;
wire [ 7:0] port_out;
wire        port_write;
wire        port_read;
wire        port_ready;
// ---------------------------------------------------------------------
reg         kb_hit     = 0;
reg  [7:0]  kb_data    = 0;
// ---------------------------------------------------------------------
wire        irq_signal;
wire [7:0]  irq;
// ---------------------------------------------------------------------

ctl_port CTLPORT
(
    .clock_cpu      (clock25),
    .port_address   (port_address),
    .port_in        (port_in),
    .port_out       (port_out),
    .port_write     (port_write),
    .port_read      (port_read),
    .port_ready     (port_ready),

    // Клавиатура
    .clock_50       (clock50),
    .kb_hit         (kb_hit),
    .kb_data        (kb_data),

    // PIC
    .irq_signal     (irq_signal),
    .irq            (irq)
);

// Реализация процессора
cpu CPU86
(
    .clock          (clock25),
    .address        (address),
    .i_data         (i_data),
    .o_data         (o_data),
    .we             (we),

    // Порты
    .port_address   (port_address),
    .port_write     (port_write),
    .port_read      (port_read),
    .port_in        (port_in),
    .port_out       (port_out),
    .port_ready     (port_ready),

    // PIC
    .irq_signal     (irq_signal),
    .irq            (irq)
);

endmodule
