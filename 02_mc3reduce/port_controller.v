module port_controller(

    input  wire         clock50,
    input  wire  [15:0] port_addr,
    output reg   [15:0] port_in,
    input  wire  [15:0] port_out,
    input  wire         port_bit,   /* Битность */
    input  wire         port_clk,   /* Запись в порт */
    input  wire         port_read,  /* Чтение из порта */

    /* Данные с PS/2 контроллера */
    input  wire [7:0]   ps2_data,
    input  wire         ps2_data_clk,

    /* Положение курсора */
    output reg [10:0]   cursor

);

/* Графический индекс */
reg [3:0]   g_index = 1'b0;
initial     cursor = 11'h0;

// Роутер
// ---------------------------------------------------------------------

always @* begin

    case (port_addr)

        16'h0060, 16'h0064: port_in = {8'h00, keyb_data};
        default: port_in = 1'b0;

    endcase

end

// ---------------------------------------------------------------------
// Скан-коды: https://ru.wikipedia.org/wiki/Скан-код

/* Обработчик клавиатуры */
reg [7:0] keyb_char    = 8'h00;     /* Последний принятый байт */
reg       keyb_ready1  = 1'b0;      /* Асинхронный статус приема */
reg       keyb_ready2  = 1'b0;      /* Acknowlegde */
wire      keyb_ready   = keyb_ready1 ^ keyb_ready2; /* Бит 0 порта 64h */
reg [1:0] keyb_jread   = 2'b00;     /* Признак только что принятого байта из порта 60h */
reg [7:0] keyb_data    = 8'h0;      /* Выходные данные для порта */
reg [7:0] keyb_xt      = 8'h0;      /* Сконвертированное AT -> XT */
reg       keyb_unpressed = 1'b0;    /* Признак "отжатой" клаваши */

always @(*) begin

    case (ps2_data)

        /* A   */ 8'h1C: keyb_xt = 8'h1E;
        /* B   */ 8'h32: keyb_xt = 8'h30;
        /* C   */ 8'h21: keyb_xt = 8'h2E;
        /* D   */ 8'h23: keyb_xt = 8'h20;
        /* E   */ 8'h24: keyb_xt = 8'h12;
        /* F   */ 8'h2B: keyb_xt = 8'h21;
        /* G   */ 8'h34: keyb_xt = 8'h22;
        /* H   */ 8'h33: keyb_xt = 8'h23;
        /* I   */ 8'h43: keyb_xt = 8'h17;
        /* J   */ 8'h3B: keyb_xt = 8'h24;
        /* K   */ 8'h42: keyb_xt = 8'h25;
        /* L   */ 8'h4B: keyb_xt = 8'h26;
        /* M   */ 8'h3A: keyb_xt = 8'h32;
        /* N   */ 8'h31: keyb_xt = 8'h31;
        /* O   */ 8'h44: keyb_xt = 8'h18;
        /* P   */ 8'h4D: keyb_xt = 8'h19;
        /* Q   */ 8'h15: keyb_xt = 8'h10;
        /* R   */ 8'h2D: keyb_xt = 8'h13;
        /* S   */ 8'h1B: keyb_xt = 8'h1F;
        /* T   */ 8'h2C: keyb_xt = 8'h14;
        /* U   */ 8'h3C: keyb_xt = 8'h16;
        /* V   */ 8'h2A: keyb_xt = 8'h2F;
        /* W   */ 8'h1D: keyb_xt = 8'h11;
        /* X   */ 8'h22: keyb_xt = 8'h2D;
        /* Y   */ 8'h35: keyb_xt = 8'h15;
        /* Z   */ 8'h1A: keyb_xt = 8'h2C;
        /* 0   */ 8'h45: keyb_xt = 8'h0B;
        /* 1   */ 8'h16: keyb_xt = 8'h02;
        /* 2   */ 8'h1E: keyb_xt = 8'h03;
        /* 3   */ 8'h26: keyb_xt = 8'h04;
        /* 4   */ 8'h25: keyb_xt = 8'h05;
        /* 5   */ 8'h2E: keyb_xt = 8'h06;
        /* 6   */ 8'h36: keyb_xt = 8'h07;
        /* 7   */ 8'h3D: keyb_xt = 8'h08;
        /* 8   */ 8'h3E: keyb_xt = 8'h09;
        /* 9   */ 8'h46: keyb_xt = 8'h0A;
        /* ~   */ 8'h0E: keyb_xt = 8'h29;
        /* -   */ 8'h4E: keyb_xt = 8'h0C;
        /* =   */ 8'h55: keyb_xt = 8'h0D;
        /* \   */ 8'h5D: keyb_xt = 8'h2B;
        /* [   */ 8'h54: keyb_xt = 8'h1A;
        /* ]   */ 8'h5B: keyb_xt = 8'h1B;
        /* ;   */ 8'h4C: keyb_xt = 8'h27;
        /* '   */ 8'h52: keyb_xt = 8'h28;
        /* ,   */ 8'h41: keyb_xt = 8'h33;
        /* .   */ 8'h49: keyb_xt = 8'h34;
        /* /   */ 8'h4A: keyb_xt = 8'h35;
        /* BS  */ 8'h66: keyb_xt = 8'h0E;
        /* SPC */ 8'h29: keyb_xt = 8'h39;
        /* TAB */ 8'h0D: keyb_xt = 8'h0F;

        /* Кнопки модификации */
        /* CAP */ 8'h58: keyb_xt = 8'h3A; /* CAPS LOCK */
        /* LSH */ 8'h12: keyb_xt = 8'h2A; /* LEFT SHIFT */
        /* LCT */ 8'h14: keyb_xt = 8'h1D; /* LEFT CTRL */
        /* LAT */ 8'h11: keyb_xt = 8'h38; /* LEFT ALT */
        /* LWI */ 8'h1F: keyb_xt = 8'h5B; /* LEFT WIN */
        /* RSH */ 8'h59: keyb_xt = 8'h36; /* RIGHT SHIFT */
        /* RWI */ 8'h27: keyb_xt = 8'h5C; /* RIGHT WIN */
        /* MNU */ 8'h2F: keyb_xt = 8'h5D; /* MENU */
        /* ENT */ 8'h5A: keyb_xt = 8'h1C; /* ENTER */

        /* Функциональная панель */
        /* ESC */ 8'h76: keyb_xt = 8'h01;
        /* F1  */ 8'h05: keyb_xt = 8'h3B;
        /* F2  */ 8'h06: keyb_xt = 8'h3C;
        /* F3  */ 8'h04: keyb_xt = 8'h3D;
        /* F4  */ 8'h0C: keyb_xt = 8'h3E;
        /* F5  */ 8'h03: keyb_xt = 8'h3F;
        /* F6  */ 8'h0B: keyb_xt = 8'h40;
        /* F7  */ 8'h83: keyb_xt = 8'h41;
        /* F8  */ 8'h0A: keyb_xt = 8'h42;
        /* F9  */ 8'h01: keyb_xt = 8'h43;
        /* F10 */ 8'h09: keyb_xt = 8'h44;
        /* F11 */ 8'h78: keyb_xt = 8'h57;
        /* F12 */ 8'h07: keyb_xt = 8'h58;
        /* SCL */ 8'h7E: keyb_xt = 8'h46;

        /* Цифровая клавиатура */
        /* NUM */ 8'h77: keyb_xt = 8'h45;
        /* *   */ 8'h7C: keyb_xt = 8'h37;
        /* -   */ 8'h7B: keyb_xt = 8'h4A;
        /* +   */ 8'h79: keyb_xt = 8'h4E;
        /* .   */ 8'h71: keyb_xt = 8'h53;
        /* 0   */ 8'h70: keyb_xt = 8'h52;
        /* 1   */ 8'h69: keyb_xt = 8'h4F;
        /* 2   */ 8'h72: keyb_xt = 8'h50;
        /* 3   */ 8'h7A: keyb_xt = 8'h51;
        /* 4   */ 8'h6B: keyb_xt = 8'h4B;
        /* 5   */ 8'h73: keyb_xt = 8'h4C;
        /* 6   */ 8'h74: keyb_xt = 8'h4D;
        /* 7   */ 8'h6C: keyb_xt = 8'h47;
        /* 8   */ 8'h75: keyb_xt = 8'h48;
        /* 9   */ 8'h7D: keyb_xt = 8'h49;

        /* E0, E1, ... */
        default: keyb_xt = ps2_data;

    endcase

end

/* Принятие данных из PS/2 */
always @(posedge clock50) begin

    /* Регистрация фронта спада и подъема */
    keyb_jread <= {keyb_jread[0], port_read};

    // Новые данные присутствуют. Асинхронный прием.
    if (ps2_data_clk) begin

        /* Этот скан-код является кодом AT, который сигнализирует, что
           клавиша отжимается. Для преобразования в XT-скан код, не нужно
           показывать, что эта клавиша "отжата" */

        if (ps2_data == 8'hF0) begin

            keyb_unpressed <= 1'b1;

        end else begin

            /* Если keyb_ready=0, то перебросить в 1, иначе оставить как 1 */
            keyb_ready1 <= keyb_ready1 ^ keyb_ready ^ 1'b1;

            /* Запись сконвертированного из AT -> XT */
            /* Если предыдущий скан-код - это признак "отжатия" клавиши, то записать 1 в 7-й бит */
            keyb_char   <= keyb_unpressed ? {1'b1, keyb_xt[6:0] } : keyb_xt;

            /* Вернуть обратно в нормальное положение */
            keyb_unpressed <= 1'b0;

        end

    end

    // Только что было чтение из порта (на обратном фронте)
    if ({keyb_jread[0], port_read} == 2'b10) begin

        case (port_addr)

            /* Порт данных */
            16'h0060: begin

                /* Скопируем последний char */
                keyb_data   <= keyb_char;

                /* Сброс статуса для порта 64h */
                keyb_ready2 <= keyb_ready2 ^ keyb_ready;

            end

            /* Порт статуса */
            16'h0064: keyb_data <= {7'h0, keyb_ready};

        endcase

    end

end

/* Запись данных в порт */
always @(negedge port_clk) begin

    case (port_addr)

        /* Index */
        16'h03d4: begin g_index <= port_out[3:0]; end

        /* Data */
        16'h03d5: case (g_index)

            4'hE: begin cursor[10:8] <= port_out[2:0]; end /* HI cursor pos */
            4'hF: begin cursor[7:0]  <= port_out[7:0]; end /* LO cursor pos */

        endcase

    endcase

end

// ---------------------------------------------------------------------

endmodule
