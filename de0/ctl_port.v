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
    input   wire [ 7:0] kb_data

);

initial port_in    = 8'hFF;
initial port_ready = 1;

// ---------------------------------------------------------------------
// Контроллер клавиатуры
// ---------------------------------------------------------------------

reg [7:0] kb_scancode   = 8'h7F;
reg       kb_latch      = 0;
reg       kb_unpress    = 0;
reg       kb_flipflop_1 = 0;
reg       kb_flipflop_2 = 0;

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

    // Если пришли новые данные с клавиатуры
    if (kb_flipflop_1 != kb_flipflop_2) begin
        kb_flipflop_2 <= kb_flipflop_1;     // Защелкнуть последнее состояние
        kb_latch      <= 1;                 // Отметить, что данные есть
    end

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

end

endmodule
