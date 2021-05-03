`timescale 10ns / 1ns

module main;

// ---------------------------------------------------------------------

reg clk = 1'b0;
reg clk25 = 1'b0;
reg clk50 = 1'b0;

reg [7:0] ps2_data = 8'h00;
reg       ps2_data_clk = 1'b0;

always #0.5 clk       = ~clk;
always #1 clk50       = ~clk50;
always #2 clk25       = ~clk25;

/* Имитация клавиатуры */
initial #2 ps2_data = 8'h76;
initial #2 ps2_data_clk = 1'b1;
initial #4 ps2_data_clk = 1'b0;

/*
initial #6 ps2_data = 8'h2E;
initial #6 ps2_data_clk = 1'b1;
initial #8 ps2_data_clk = 1'b0;
*/

initial begin clk = 1; #2000 $finish; end
initial begin $dumpfile("main.vcd"); $dumpvars(0, main); end

// ---------------------------------------------------------------------

reg  [7:0]  i; /* Вход CPU */
wire [7:0]  o; /* Выход из CPU */
wire [15:0] a;
wire        w; 
reg  [1:0]  flw = 2'b00; 

// ------------------------------------- Регистровый файл --------------
reg [ 7:0] memory[65536];

/*
    0000-7FFF  Общая память (32кб)
    B800-BFFF  Видеопамять текстовая (2k)
    C000-FFFF  BIOS (8кб)
*/

// Ревизия 1
initial begin $readmemh("init/ram.hex",  memory, 16'h0000); end
initial begin $readmemh("init/bios.hex", memory, 16'hC000); end 

always @(posedge clk) begin

    // Чтение данных из памяти
    i <= memory[ a ];
    
    // Запись данных в память
    if (w) memory[ a ] <= o;
    
end

wire  [15:0] port_addr;
wire  [15:0] port_in;
wire  [15:0] port_out;
wire         port_bit;
wire         port_clk;
wire         port_read;
wire  [10:0] cursor;

/* Распределитель портов */
port_controller PortCTRL(

    clk50,
    port_addr, /* Адрес */
    port_in,   /* Вход (для CPU) */
    port_out,  /* Вход (для контроллера) */
    port_bit,  /* Битность данных */
    port_clk,  /* Строб записи */
    port_read, /* Строб чтения */
    
    /* PS/2 интерфейс */
    ps2_data,       /* Принятые данные */
    ps2_data_clk,   /* Строб принятых данных */
    
    cursor
);

// ------------------------------------- Центральный процессор ---------
cpu CPU(1'b0, 
        clk, clk25, i, o, a, w, 
        port_addr, port_in, port_out, port_bit, port_clk, port_read);
    
endmodule
