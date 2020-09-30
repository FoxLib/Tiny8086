// Вычисление четности
uint8_t parity(uint8_t b) {

    b = (b >> 4) ^ (b & 15);
    b = (b >> 2) ^ (b & 3);
    b = (b >> 1) ^ (b & 1);
    return !b;
}

// Вычисление АЛУ двух чисел 8 (i_w=0) или 16 бит (i_w=1)
// id = 0..7 ADD|OR|ADC|SBB|AND|SUB|XOR|CMP
uint16_t arithlogic(char id, char i_w, uint16_t op1, uint16_t op2) {

    uint32_t res = 0;

    // Расчет битности
    int bits = i_w ? 0x08000 : 0x080;
    int bitw = i_w ? 0x0FFFF : 0x0FF;
    int bitc = i_w ? 0x10000 : 0x100;

    // Выбор режима работы
    switch (id & 7) {

        case 0: { // ADD

            res = op1 + op2;

            flags.c = !!(res & bitc);
            flags.a = !!((op1 & 15) + (op2 & 15) >= 0x10);
            // flags.o = ..
            break;
        }
    }

    // Эти флаги проставляются для всех
    flags.p =  parity(res);
    flags.z = !(res & bitw);
    flags.s = !!(res & bits);
}

