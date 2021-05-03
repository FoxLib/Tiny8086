module marsohod2(

    /* ----------------
     * Archectural Marsohod2
     * ---------------- */

    // CLOCK    100 Mhz
    input   wire        clk,

    // LED      4
    output  reg  [3:0]  led,

    // KEYS     2
    input   wire [1:0]  keys,

    // ADC      8 bit
    output  wire        adc_clock_20mhz,
    input   wire [7:0]  adc_input,

    // SDRAM
    output  wire        sdram_clock,
    output  wire [11:0] sdram_addr,
    output  wire [1:0]  sdram_bank,
    inout   wire [15:0] sdram_dq,
    output  wire        sdram_ldqm,
    output  wire        sdram_udqm,
    output  wire        sdram_ras,
    output  wire        sdram_cas,
    output  wire        sdram_we,

    // VGA
    output  wire [4:0]  vga_red,
    output  wire [5:0]  vga_green,
    output  wire [4:0]  vga_blue,
    output  wire        vga_hs,
    output  wire        vga_vs,

    // FTDI (PORT-B)
    input   wire        ftdi_rx,
    output  wire        ftdi_tx,

    /* ----------------
     * Extension Shield
     * ---------------- */

    // USB-A    2 pins
    inout   wire [1:0]  usb,

    // SOUND    2 channel
    output  wire        sound_left,
    output  wire        sound_right,

    // PS/2     keyb / mouse
    inout   wire [1:0]  ps2_keyb, // ps2_keyb[0]  data, ps2_keyb[1]  clk
    inout   wire [1:0]  ps2_mouse // ps2_mouse[0] data, ps2_mouse[1] clk
);
// --------------------------------------------------------------------------

/* Делитель частоты до 25 Мгц */
reg [1:0] div = 2'b00;
reg cpu_latency = 1'b0;
reg clk25 = 1'b0;

always @(posedge clk) begin

    div <= div + 1'b1;

    /* Нормальное выполнение */
    if (cpu_latency) begin

        // kbd_reset <= ps2_port_init; /* Случай для экстренной перезагрузки */
        clk25 <= div[1];

    /* Для того, чтобы успел первый опкод скачаться успешно */
    end else if (div == 2'b11) begin

        cpu_latency <= 1'b1;
        kbd_reset   <= 1'b0;

    /* Инициализация PS/2 keyboard */
    end else begin

        kbd_reset   <= 1'b1;

    end

end

wire [15:0] a;
reg  [7:0]  i;
wire [7:0]  o;
wire w;
reg  [1:0]  awm = 1'b0;

wire [7:0]  q_rom;
wire [7:0]  q_ram;
wire [7:0]  q_vid;
reg         wren_vram;
reg         wren_cram;

biosrom BIOSROM( /* 16Kb */

    .clock   (clk),
    .addr_rd (a[13:0]),
    .q       (q_rom),

    /* Программирование */
    .addr_wr (prg_addr),
    .data_wr (prg_idata),
    .wren    (prg_wren && prg_negedge == 2'b10),

);

comram COMMONRAM( /* 16Kb */

    .clock   (clk),
    .addr_rd (a[13:0]),
    .q       (q_ram),

    .addr_wr (a[13:0]),
    .data_wr (o),
    .wren    (wren_cram),
);

/*
 * Контроллер клавиатуры PS/2
 */

reg         kbd_reset = 1'b0;
reg [7:0]   ps2_command = 1'b0;
reg         ps2_command_send = 1'b0;
wire [7:0]  ps2_data;
wire        ps2_data_clk;

always @(posedge div[0]) if (ps2_data_clk) led[3:1] <= ps2_data[2:0];

PS2_Controller Keyboard(

    /* Вход */
    .CLOCK_50       (div[0]),
    .reset          (kbd_reset),

    /* Ввод-вывод */
    .PS2_CLK        (ps2_keyb[1]),
    .PS2_DAT        (ps2_keyb[0]),

    /* Выход полученных */
    .received_data      (ps2_data),
    .received_data_en   (ps2_data_clk)
);

wire [15:0] port_addr;
wire [15:0] port_in;
wire [15:0] port_out;
wire        port_bit;
wire        port_clk;
wire        port_read;

/* Распределитель портов */
port_controller PortCTRL(

    .clock50    (div[0]),    /* 50 Mhz */
    .port_addr  (port_addr), /* Адрес */
    .port_in    (port_in),   /* Вход (для CPU) */
    .port_out   (port_out),  /* Вход (для контроллера) */
    .port_bit   (port_bit),  /* Битность данных */
    .port_clk   (port_clk),  /* Строб записи */
    .port_read  (port_read), /* Строб чтения */

    /* PS/2 интерфейс */
    .ps2_data     (ps2_data),       /* Принятые данные */
    .ps2_data_clk (ps2_data_clk),   /* Строб принятых данных */

    /* VGA */
    .cursor      (cursor)       /* Позиция курсора VGA */

);

// Keyboard Port Controller (пока что только чтение)
// http://ru.osdev.wikia.com/wiki/%D0%9A%D0%BE%D0%BD%D1%82%D1%80%D0%BE%D0%BB%D0%BB%D0%B5%D1%80_%D0%B8%D0%BD%D1%82%D0%B5%D1%80%D1%84%D0%B5%D0%B9%D1%81%D0%B0_PS/2

// ---------------------------------------------------------------------
// Объявляем нужные провода
wire [11:0] adapter_font;
wire [ 7:0] adapter_data;
wire [11:0] font_char_addr;
wire [ 7:0] font_char_data;
wire [10:0] cursor;

// Назначаем пины для модуля
// .green - внутренее название пина в самом модуле
// vga_green - внешнее (отсюда)

vga VGA_ADAPTER(

    .clk    (clk),
    .red    (vga_red),
    .green  (vga_green),
    .blue   (vga_blue),
    .hs     (vga_hs),
    .vs     (vga_vs),

    // Источник знакогенератора
    .adapter_font (adapter_font),
    .adapter_data (adapter_data),

    // Сканирование символов
    .font_char_addr (font_char_addr),
    .font_char_data (font_char_data),

    .cursor (cursor)

);

// Здесь хранятся шрифты (знакогенератор)
fontrom VGA_FONT_ROM(

    .clock      (clk),          // Тактовая частота - 100 Мгц для памяти
    .addr_rd    (adapter_font), // Адаптер будет указывать адрес, который ему интересен,
                                // чтобы узнать значение следующих 8 бит для шрифта
    .q          (adapter_data)  // Здесь будет это значение через 2 такта на скорости 100 Мгц
);

// Информация о символах и атрибутах
fontram VGA_VIDEORAM(

    .clock      (clk),            // Тактовая частота - 100 Мгц для памяти
    .addr_rd    (font_char_addr), // В памяти сначала хранится символ, потом его цвет
    .q          (font_char_data), // Тут будет результат

    /* Взаимодействие с процессором */
    .addr_wr    (a[11:0]),
    .data_wr    (o),
    .wren       (wren_vram),
    .qw         (q_vid),
);
// ---------------------------------------------------------------------

/* Отложенная на 1 такт запись в память */
always @(posedge clk) begin awm[1:0] <= {awm[0], clk25}; end

/* Позитивный фронт на запись в память */
wire awf = (awm == 2'b01);

/* Маппинг памяти */
always @* begin

    casex (a)

        // Общая быстрая память (0000-3FFF) 16 Kb
        16'b00xx_xxxx_xxxx_xxxx: begin i = q_ram; {wren_vram, wren_cram} = {1'b0, w && awf}; end

        // Видеопамять текстовая (B000-BFFF) 4 Kb
        16'b1011_xxxx_xxxx_xxxx: begin i = q_vid; {wren_vram, wren_cram} = {w && awf, 1'b0}; end

        // Область BIOS памяти (C000-FFFF) 16Kb
        16'b11xx_xxxx_xxxx_xxxx: begin i = q_rom; {wren_vram, wren_cram} = 2'b00; end

        // Любая другая область
        default: begin i = 8'h00; {wren_vram, wren_cram} = 2'b00; end

    endcase

end

// https://wiki.osdev.org/VGA_Fonts -- Vga I/O

cpu CPU( /* Процессор */

    prg_enable | ~keys[0],   // RESET + кнопкой
    (clk),                   // 100 мегагерц
    (clk25 && cpu_latency),  // 25 мегагерц
    i,      // Data In
    o,      // Data Out
    a,      // Aдрес
    w,      // Запись [o] на HIGH уровне

    /* Работа с портами */
    port_addr,
    port_in,
    port_out,
    port_bit,
    port_clk,
    port_read

);

/*
 * Адаптер частот PLL
 */

wire locked;
wire clock_25;  // 25.00
wire clock_12;  // 12.00
wire clock_6;   //  6.00

pll PLL(

    .clk        (clk),          // Входящие 100 Мгц
    .locked     (locked),       // 0 - устройство генератора ещё не сконфигурировано, 1 - готово и стабильно
    .c0         (clock_25),     // 25,0 Mhz
    .c1         (clock_12),     // 12,0 Mhz
    .c2         (clock_6)       //  6,0 Mhz

);

/*
 * Последовательный порт
 * Скорость 230400 бод или 25600 байт в секунду (25 кбайт/с)
 */

wire [7:0]  rx_byte;
wire        rx_ready;
wire        clk12;
reg         rom_bank_wr;

serial SERIAL(

    .clk12    (locked & clock_12),  // Частота 12.0 Mhz
    .rx       (ftdi_rx),            // Входящие данные
    .rx_byte  (rx_byte),            // Исходящий байт (8 bit)
    .rx_ready (rx_ready)            // Строб готовности

);

reg [7:0]  prg_idata = 1'b0;  /* Данные для записи */
reg [13:0] prg_addr = 1'b0;   /* Адрес */
reg        prg_wren = 1'b0;   /* Производится запись в память */
reg        prg_enable = 1'b0; /* Программирование включено */
reg [1:0]  prg_negedge = 2'b00;

/* Регистрация negedge rx_ready */
always @(posedge clk) prg_negedge <= {prg_negedge[0], rx_ready};

// Включение программатора 32 КБ ROM памяти
always @(posedge rx_ready) begin

    prg_idata <= rx_byte;

    if (prg_enable == 1'b0) begin

        prg_enable <= 1'b1;
        prg_wren   <= 1'b1;
        prg_addr   <= 16'h0000;
        led[0]     <= 1'b1;

    end
    else begin

        if (prg_addr == 16'h3FFE) /* -2 от реального */ begin
            prg_enable <= 1'b0;
            prg_wren   <= 1'b0;
            led[0]     <= 1'b0;
        end

        prg_addr <= prg_addr + 1'b1;

    end

end

endmodule
