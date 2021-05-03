// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
module comram (clock, addr_rd, addr_wr, data_wr, wren, q, qw);
input    clock;
input    [13:0] addr_wr;
input    [7:0] data_wr;
input          wren;
input    [13:0] addr_rd;
output   [7:0] q;
output   [7:0] qw;
wire     [7:0] sub_wire0;
wire     [7:0] sub_wire1;
wire     [7:0] q  = sub_wire0[7:0];
wire     [7:0] qw = sub_wire1[7:0];
altsyncram	altsyncram_component (
    .clock0 (clock),
    .wren_a (1'b0),
    .wren_b (wren),
    .address_a (addr_rd),
    .address_b (addr_wr),
    .data_a (8'h0),
    .data_b (data_wr),
    .q_a (sub_wire0),
    .q_b (sub_wire1),
    .aclr0 (1'b0),
    .aclr1 (1'b0),
    .addressstall_a (1'b0),
    .addressstall_b (1'b0),
    .byteena_a (1'b1),
    .byteena_b (1'b1),
    .clock1 (1'b1),
    .clocken0 (1'b1),
    .clocken1 (1'b1),
    .clocken2 (1'b1),
    .clocken3 (1'b1),
    .eccstatus (),
    .rden_a (1'b1),
    .rden_b (1'b1));
defparam
    altsyncram_component.address_reg_b = "CLOCK0",
    altsyncram_component.clock_enable_input_a = "BYPASS",
    altsyncram_component.clock_enable_input_b = "BYPASS",
    altsyncram_component.clock_enable_output_a = "BYPASS",
    altsyncram_component.clock_enable_output_b = "BYPASS",
    altsyncram_component.indata_reg_b = "CLOCK0",
    altsyncram_component.init_file = "ram.mif",
    altsyncram_component.intended_device_family = "Cyclone III",
    altsyncram_component.lpm_type = "altsyncram",
    altsyncram_component.numwords_a = 16384,
    altsyncram_component.numwords_b = 16384,
    altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
    altsyncram_component.outdata_aclr_a = "NONE",
    altsyncram_component.outdata_aclr_b = "NONE",
    altsyncram_component.outdata_reg_a = "CLOCK0",
    altsyncram_component.outdata_reg_b = "CLOCK0",
    altsyncram_component.power_up_uninitialized = "FALSE",
    altsyncram_component.ram_block_type = "M9K",
    altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
    altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_WITH_NBE_READ",
    altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_WITH_NBE_READ",
    altsyncram_component.widthad_a = 14,
    altsyncram_component.widthad_b = 14,
    altsyncram_component.width_a = 8,
    altsyncram_component.width_b = 8,
    altsyncram_component.width_byteena_a = 1,
    altsyncram_component.width_byteena_b = 1,
    altsyncram_component.wrcontrol_wraddress_reg_b = "CLOCK0";
endmodule
