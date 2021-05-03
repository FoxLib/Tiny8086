localparam

    sub_fetch       = 0,    // Базовый опкод
    sub_extended    = 1,    // Считывание расширенного кода
    sub_modrm       = 2,    // Прочитать и разобрать modrm
    sub_exec        = 3,    // Исполнить инструкции
    sub_wb          = 4;    // Обратная запись в modrm

localparam

    seg_es = 0, reg_ax = 0, reg_sp = 4, reg_al = 0, reg_ah = 4,
    seg_cs = 1, reg_cx = 1, reg_bp = 5, reg_cl = 1, reg_ch = 5,
    seg_ss = 2, reg_dx = 2, reg_si = 6, reg_dl = 2, reg_dh = 6,
    seg_ds = 3, reg_bx = 3, reg_di = 7, reg_bl = 3, reg_bh = 7;

localparam

    alu_add = 0, alu_and = 4, alu_rol = 8,  alu_shl = 12,
    alu_or  = 1, alu_sub = 5, alu_ror = 9,  alu_shr = 13,
    alu_adc = 2, alu_xor = 6, alu_rcl = 10, alu_sh2 = 14,
    alu_sbb = 3, alu_cmp = 7, alu_rcr = 11, alu_sar = 15;

// https://ru.wikipedia.org/wiki/Регистр_флагов
localparam

    flag_o = 11,
    flag_d = 10,
    flag_i =  9,
    flag_t =  8,
    flag_s =  7,
    flag_z =  6,
    flag_a =  4,
    flag_p =  2,
    flag_c =  0;
