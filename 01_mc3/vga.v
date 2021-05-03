module vga
(
    // Опорная частота 25 Mhz
    input   wire        CLOCK,

    // Выходные данные
    output  reg  [4:0]  VGA_R,      // 4 бит на красный
    output  reg  [5:0]  VGA_G,      // 4 бит на зеленый
    output  reg  [4:0]  VGA_B,      // 4 бит на синий
    output  wire        VGA_HS,     // горизонтальная развертка
    output  wire        VGA_VS,     // вертикальная развертка

    // Знакогенератор и видеопамять
    output  reg  [11:0] FONT_ADDR,
    input   wire [ 7:0] FONT_DATA,
    output  reg  [11:0] CHAR_ADDR,
    input   wire [ 7:0] CHAR_DATA,

    // Передаваемый параметр курсора (от 1 до 4000 включительно)
    // Если CURSOR=0, то он не виден
    input   wire [10:0] CURSOR
);

// ---------------------------------------------------------------------

// Тайминги для горизонтальной развертки (640)
parameter hz_visible = 640;
parameter hz_front   = 16;
parameter hz_sync    = 96;
parameter hz_back    = 48;
parameter hz_whole   = 800;

// Тайминги для вертикальной развертки (400)
parameter vt_visible = 400;
parameter vt_front   = 12;
parameter vt_sync    = 2;
parameter vt_back    = 35;
parameter vt_whole   = 449;

// ---------------------------------------------------------------------
assign VGA_HS = x  < (hz_back + hz_visible + hz_front); // NEG.
assign VGA_VS = y >= (vt_back + vt_visible + vt_front); // POS.
// ---------------------------------------------------------------------

wire        xmax = (x == hz_whole - 1);
wire        ymax = (y == vt_whole - 1);
reg  [10:0] x    = 0;
reg  [10:0] y    = 0;
wire [ 9:0] X    = x - hz_back + 8;         // X=[0..639] Предзагрузка символа
wire [ 8:0] Y    = y - vt_back;             // Y=[0..399]
wire [10:0] ID   = X[9:3] + Y[8:4] * 80;    // Рисуемый символ
// ---------------------------------------------------------------------
reg  [ 7:0] _char; // Битовая маска
reg  [ 7:0] _attr; // Атрибут
reg         flash; // Мерцание курсора
reg  [23:0] timer; // Для курсора
// ---------------------------------------------------------------------
// Если появляется курсор [1..4000], то он использует нижние 2 строки у линии
wire maskbit = (_char[ 3'h7 ^ X[2:0] ]) | (flash && ID == CURSOR && Y[3:0] >= 14);

// Разбираем цветовую компоненту (нижние 4 бита отвечают за цвет символа)
wire [15:0] forecolor =

    // R(5 бит) G(6 бит) B(5 бит(
    _attr[3:0] == 4'h0 ? { 5'h03, 6'h03, 5'h03 } : // 0 Черный (почти)
    _attr[3:0] == 4'h1 ? { 5'h00, 6'h00, 5'h0F } : // 1 Синий (темный)
    _attr[3:0] == 4'h2 ? { 5'h00, 6'h1F, 5'h00 } : // 2 Зеленый (темный)
    _attr[3:0] == 4'h3 ? { 5'h00, 6'h1F, 5'h0F } : // 3 Бирюзовый (темный)
    _attr[3:0] == 4'h4 ? { 5'h0F, 6'h00, 5'h00 } : // 4 Красный (темный)
    _attr[3:0] == 4'h5 ? { 5'h0F, 6'h00, 5'h0F } : // 5 Фиолетовый (темный)
    _attr[3:0] == 4'h6 ? { 5'h0F, 6'h1F, 5'h00 } : // 6 Коричневый
    _attr[3:0] == 4'h7 ? { 5'h0F, 6'h1F, 5'h0F } : // 7 Серый -- тут что-то не то
    _attr[3:0] == 4'h8 ? { 5'h07, 6'h0F, 5'h07 } : // 8 Темно-серый
    _attr[3:0] == 4'h9 ? { 5'h00, 6'h00, 5'h1F } : // 9 Синий (темный)
    _attr[3:0] == 4'hA ? { 5'h00, 6'h3F, 5'h00 } : // 10 Зеленый
    _attr[3:0] == 4'hB ? { 5'h00, 6'h3F, 5'h1F } : // 11 Бирюзовый
    _attr[3:0] == 4'hC ? { 5'h1F, 6'h00, 5'h00 } : // 12 Красный
    _attr[3:0] == 4'hD ? { 5'h1F, 6'h00, 5'h1F } : // 13 Фиолетовый
    _attr[3:0] == 4'hE ? { 5'h1F, 6'h3F, 5'h00 } : // 14 Желтый
                         { 5'h1F, 6'h3F, 5'h1F };  // 15 Белый

// Цветовая компонента фона (только 8 цветов)
wire [15:0] backcolor =

    // R(5 бит) G(6 бит) B(5 бит(
    _attr[6:4] == 3'd0 ? { 5'h03, 6'h03, 5'h03 } : // 0 Черный (почти)
    _attr[6:4] == 3'd1 ? { 5'h00, 6'h00, 5'h0F } : // 1 Синий (темный)
    _attr[6:4] == 3'd2 ? { 5'h00, 6'h1F, 5'h00 } : // 2 Зеленый (темный)
    _attr[6:4] == 3'd3 ? { 5'h00, 6'h1F, 5'h0F } : // 3 Бирюзовый (темный)
    _attr[6:4] == 3'd4 ? { 5'h0F, 6'h00, 5'h00 } : // 4 Красный (темный)
    _attr[6:4] == 3'd5 ? { 5'h0F, 6'h00, 5'h0F } : // 5 Фиолетовый (темный)
    _attr[6:4] == 3'd6 ? { 5'h0F, 6'h1F, 5'h00 } : // 6 Коричневый
                         { 5'h0F, 6'h1F, 5'h0F };  // 7 Серый

// Главный цикл обработки текстового видеовывода
always @(posedge CLOCK) begin

    // Кадровая развертка
    x <= xmax ?         0 : x + 1;
    y <= xmax ? (ymax ? 0 : y + 1) : y;

    // Вывод окна видеоадаптера
    if (x >= hz_back && x < hz_visible + hz_back &&
        y >= vt_back && y < vt_visible + vt_back)
    begin
        // 1 Если бита нет, рисовать задний план
        // 2 Если бит есть, и есть бит 7 атрибута и flash активен, рисовать задний план - иначе передний       
        {VGA_R, VGA_G, VGA_B} <= maskbit ? (_attr[7] & flash ? backcolor : forecolor) : backcolor;
    end else
        {VGA_R, VGA_G, VGA_B} <= 16'b0;

end

// Извлечение битовой маски и атрибутов для генерации шрифта
always @(posedge CLOCK) begin

    case (X[2:0])

        0:  begin CHAR_ADDR    <= {ID, 1'b0}; end
        1:  begin CHAR_ADDR[0] <= 1'b1;
                  FONT_ADDR    <= {CHAR_DATA, Y[3:0]};
            end
        7:  begin _attr <= CHAR_DATA;
                  _char <= FONT_DATA;
            end

    endcase

end

// Таймер, 0.5 с
always @(posedge CLOCK) begin

    // 12,5 Мгц. Каждые 0,5 секунды перебрасывается регистр flash
    if (timer == 12500000) begin
        flash <= ~flash;
        timer <= 1'b0;
    end else
        timer <= timer + 1;

end

endmodule
