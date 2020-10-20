/**
 * Контроллер портов
 */

module ctl_port
(
    // Общий интерфейс с процессором
    input   wire        clock_cpu,          // Опорный сигнал от процессора
    input   wire [15:0] port_address,       // Адрес порта
    output  reg  [ 7:0] port_in,            // -> (к процессору)
    input   wire [ 7:0] port_out,           // <- (от процессора)
    input   wire        port_write,         // Сигнал записи в порт
    input   wire        port_read,          // Сигнал чтения
    output  reg         port_ready,         // Готовность (reserved)

    // Клавиатура
    input   wire        clock_50,
    input   wire        kb_hit,
    input   wire [ 7:0] kb_data,

    // PIC
    output  wire        irq_signal,
    output  wire [ 7:0] irq
);

initial port_in    = 8'hFF;
initial port_ready = 1;

assign  irq_signal = pic_dev;
assign  irq        = pic_irq;

// ---------------------------------------------------------------------
// PIC
// ---------------------------------------------------------------------

// Маска для аппаратных прерываний
reg [15:0] pic_irr = 16'b1111_1111_1111_1100;

// Счетчик вызова конкретного прерывания
reg        pic_dev = 1'b0;

// Номер последнего прерывания
reg [ 7:0] pic_irq = 8'h00;

// Если =1, то ожидание разблокирование через out $20,$20
reg        pic_block = 1'b0;

// ---------------------------------------------------------------------
// Контроллер клавиатуры
// ---------------------------------------------------------------------

reg [7:0] kb_scancode   = 8'h7F;    // Полученный скан-код от клавиатуры
reg       kb_latch      = 0;        // Признак наличия новых данных от kbd
reg       kb_unpress    = 0;        // Клавиша была отпущена (=1)
reg       kb_flipflop_1 = 0;        // Согласование тактов 50 мгц
reg       kb_flipflop_2 = 0;        // С тактами 25 мгц

always @(posedge clock_50) begin

    // Есть данные от клавиатуры
    if (kb_hit) begin

        // Признак отпущенной клавиши
        if (kb_data == 8'hF0) kb_unpress <= 1;

        // Пришел скан-код
        else begin

            kb_scancode   <= kb_data; // @todo +unpress
            kb_flipflop_1 <= ~kb_flipflop_1;
            kb_unpress    <= 0;

        end

    end

end

// ---------------------------------------------------------------------
// Обработка сигналов от процессора
// ---------------------------------------------------------------------

always @(posedge clock_cpu) begin

    // @todo Запрос прерывания таймера

    // Если пришли новые данные с клавиатуры
    if (kb_flipflop_1 != kb_flipflop_2) begin

        // Защелкнуть последнее состояние и отметить что данные есть
        kb_flipflop_2 <= kb_flipflop_1;
        kb_latch      <= 1;

        // INT#9 Keyboard Interrupt (вызывается если размаскирован 1-й бит)
        if ({pic_irr[1], pic_block} == 2'b00)
        begin pic_dev <= ~pic_dev; pic_irq <= 9; pic_block <= 1'b1; end

    end

    // Встроить логику обработки нескольких одновременных irq

    // Процессор запросил чтение из порта
    if (port_read) begin

        case (port_address)

            // Чтение последнего скан-кода
            16'h60: begin port_in <= kb_scancode; end

            // Сброс бита готовности при чтении порта состояния
            16'h64: begin port_in <= kb_latch; kb_latch <= 0; end

            // Неиспользуемый порт
            default: port_in <= 8'hFF;

        endcase

    end

    // Процессор пишет в порт
    if (port_write) begin

        case (port_address)

            // x010_0000 Отсылка EOI Master/Slave не имеет значения
            16'h20: begin if (port_out[5]) pic_block <= 0; end

        endcase

    end

end

endmodule
