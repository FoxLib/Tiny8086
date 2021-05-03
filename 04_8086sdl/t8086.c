#include <time.h>
#include <sys/timeb.h>
#include <memory.h>
#include <unistd.h>
#include <fcntl.h>
#include "SDL.h"
#include "t8086.h"
#include "helpers.c"

// Выполнение инструкции
void step() {

    opcode_id = fetch_opcode();

    // Если есть байт modrm, запустить его разбор
    if (opcodemap_modrm[opcode_id]) get_modrm();

    // Выполнение инструкции
    switch (opcode_id) {

        // Базовые инструкции АЛУ
        case 0x00: case 0x01: case 0x02: case 0x03: // ADD modrm
        case 0x08: case 0x09: case 0x0A: case 0x0B: // OR  modrm
        case 0x10: case 0x11: case 0x12: case 0x13: // ADC modrm
        case 0x18: case 0x19: case 0x1A: case 0x1B: // SBB modrm
        case 0x20: case 0x21: case 0x22: case 0x23: // AND modrm
        case 0x28: case 0x29: case 0x2A: case 0x2B: // SUB modrm
        case 0x30: case 0x31: case 0x32: case 0x33: // XOR modrm
        case 0x38: case 0x39: case 0x3A: case 0x3B: { // CMP modrm

            i_sel  = (opcode_id & 0x38) >> 3; // Режим работы АЛУ
            i_dir  = !!(opcode_id & 2); // Направление
            i_size = opcode_id & 1; // Размер byte | word

            // rm, r или r, rm
            i_op1  = i_dir ? get_reg(i_size) : get_rm(i_size);
            i_op2  = i_dir ? get_rm(i_size)  : get_reg(i_size);

            // Вычисление операндов
            i_res  = arithlogic(i_sel, i_size, i_op1, i_op2);

            // Запись результата обратно в регистр или в память
            if (i_sel != ALU_CMP) {

                if (i_dir) put_reg(i_size, i_res);
                    else   put_rm(i_size, i_res);
            }

            break;
        }

        // Базовые АЛУ с AL/AX
        case 0x04: case 0x05: case 0x0C: case 0x0D: // ADD | OR
        case 0x14: case 0x15: case 0x1C: case 0x1D: // ADC | SBB
        case 0x24: case 0x25: case 0x2C: case 0x2D: // AND | SUB
        case 0x34: case 0x35: case 0x3C: case 0x3D: { // XOR | CMP

            // Режим работы АЛУ
            i_sel  = (opcode_id & 0x38) >> 3;
            i_size = opcode_id & 1;

            // Операнды
            i_op1  = i_size ? regs16[REG_AX] : regs[REG_AL]; // AL, AX
            i_op2  = fetch(i_size + 1); // 1 или 2 байта

            // Вычисление
            i_res  = arithlogic(i_sel, i_size, i_op1, i_op2);

            if (i_sel != ALU_CMP) {

                if (i_size) regs16[REG_AX] = i_res;
                       else regs[REG_AL] = i_res;
            }

            break;
        }

        // DAA
        case 0x27: {

            // Раунд 1: Нижний ниббл
            if (((regs[REG_AL] & 0xF) > 9) || flags.a) {

                i_tmp = regs[REG_AL] + 6;
                regs[REG_AL] = i_tmp;
                flags.c = !!(i_tmp & 0xFF00);
                flags.a = 1;
            }

            // Раунд 2: Верхний ниббл
            if ((regs[REG_AL] > 0x9F) || flags.c) {

                regs[REG_AL] += 0x60;
                flags.c = 1;
            }

            // Установка флагов
            i_tmp = regs[REG_AL];

            flags.s = !!(i_tmp & 0x80);
            flags.z = !i_tmp;
            flags.p = parity(i_tmp);
            break;
        }

        // DAS
        case 0x2F: {

            old_cf  = flags.c;
            flags.c = 0;
            i_op1   = regs[REG_AL];

            // Раунд 1: Нижний ниббл
            if (((i_op1 & 0x0F) > 9) || flags.a) {

                i_tmp = regs[REG_AL] - 6;

                regs[REG_AL] = i_tmp;
                flags.c = !!(i_tmp & 0xFF00) | old_cf;
                flags.a = 1;

            } else {
                flags.a = 0;
            }

            // Раунд 2: Верхний ниббл
            if ((i_op1 > 0x99) || flags.c) {

                regs[REG_AL] -= 0x60;
                flags.c = 1;
            }

            // Установка флагов
            i_tmp = regs[REG_AL];

            flags.s = !!(i_tmp & 0x80);
            flags.z = !i_tmp;
            flags.p = parity(i_tmp);
            break;
        }

        // AAA
        case 0x37: {

            if ((regs[REG_AL] & 0x0F) > 9 || flags.a) {
                regs16[REG_AX] += 0x106;
                flags.a = 1;
                flags.c = 1;
            } else {
                flags.a = 0;
                flags.c = 0;
            }
            regs[REG_AL] &= 0x0F;
            break;
        }

        // AAS
        case 0x3F: {

            if ((regs[REG_AL] & 0x0F) > 9 || flags.a) {
                regs16[REG_AX] -= 6;
                regs[REG_AH] -= 1;
                flags.a = 1;
                flags.c = 1;
            } else {
                flags.a = 0;
                flags.c = 0;
            }
            regs[REG_AL] &= 0x0F;
            break;
        }

        // PUSH sreg
        case 0x06: case 0x0E: case 0x16: case 0x1E: {

            push(regs16[REG_ES + ((opcode_id >> 3) & 3)]);
            break;
        }

        // POP sreg
        case 0x07: case 0x17: case 0x1F: {

            regs16[REG_ES + ((opcode_id >> 3) & 3)] = pop();
            break;
        }

        // INC r16
        case 0x40: case 0x41: case 0x42: case 0x43:
        case 0x44: case 0x45: case 0x46: case 0x47:

        // DEC r16
        case 0x48: case 0x49: case 0x4A: case 0x4B:
        case 0x4C: case 0x4D: case 0x4E: case 0x4F: {

            old_cf = flags.c;
            i_op1 = regs16[opcode_id & 7];
            regs16[opcode_id & 7] = arithlogic(opcode_id & 8 ? ALU_SUB : ALU_ADD, 1, i_op1, 1);
            flags.c = old_cf;
            break;
        }

        // PUSH r16
        case 0x50: case 0x51: case 0x52: case 0x53:
        case 0x54: case 0x55: case 0x56: case 0x57: {

            push(regs16[opcode_id & 7]);
            break;
        }

        // POP r16
        case 0x58: case 0x59: case 0x5A: case 0x5B:
        case 0x5C: case 0x5D: case 0x5E: case 0x5F: {

            regs16[opcode_id & 7] = pop();
            break;
        }

        // PUSHA
        case 0x60: {

            i_tmp = regs16[REG_SP];
            for (int i = 0; i < 8; i++)
                push(i == REG_SP ? i_tmp : regs16[i]);

            break;
        }

        // POPA
        case 0x61: {

            for (int i = 7; i >= 0; i--) {
                if (i == REG_SP) i_tmp = pop();
                else regs16[i] = pop();
            }
            regs16[REG_SP] = i_tmp;
            break;
        }

        // PUSH imm16, i8
        case 0x68: push(fetch(2)); break;
        case 0x6A: i_tmp = fetch(1); push(i_tmp & 0x80 ? i_tmp | 0xFF00 : i_tmp); break;

        // Jccc b8
        case 0x70: case 0x71: case 0x72: case 0x73:
        case 0x74: case 0x75: case 0x76: case 0x77:
        case 0x78: case 0x79: case 0x7A: case 0x7B:
        case 0x7C: case 0x7D: case 0x7E: case 0x7F: {

            i_tmp = (signed char) fetch(1);
            if (cond(opcode_id & 15))
                reg_ip += i_tmp;

            break;
        }

        // Групповые инструкции АЛУ
        case 0x80: case 0x82: // alu rm, i8
        case 0x81:   // alu rm, i16
        case 0x83: { // alu rm16, i8

            i_size = opcode_id & 1;
            i_op2  = opcode_id == 0x81 ? fetch(2) : fetch(1);

            // Знаковое расширение для 0x83 инструкции
            if (opcode_id == 0x83 && (i_op2 & 0x80)) i_op2 |= 0xFF00;

            // Вычисление
            i_res = arithlogic(i_reg, i_size, get_rm(i_size), i_op2);

            // Сохранение результата
            if (i_reg != ALU_CMP) put_rm(i_size, i_res);
            break;
        }

        // TEST rm, r
        case 0x84: case 0x85: {

            i_size = opcode_id & 1;
            arithlogic(ALU_AND, i_size, get_rm(i_size), get_reg(i_size));
            break;
        }

        // XCHG rm, r
        case 0x86:
        case 0x87: {

            i_size = opcode_id & 1;
            i_op1  = get_rm(i_size);
            i_op2 = get_reg(i_size);
            put_rm(i_size, i_op2);
            put_reg(i_size, i_op1);
            break;
        }

        // MOV rm|r
        case 0x88: put_rm(0, regs[REG8(i_reg)]); break;
        case 0x89: put_rm(1, regs16[i_reg]); break;
        case 0x8A: regs[REG8(i_reg)] = get_rm(0); break;
        case 0x8B: regs16[i_reg] = get_rm(1); break;

        // MOV rm16, seg
        case 0x8C: put_rm(1, regs16[REG_ES + (i_reg & 3)]); break;

        // LEA rm16, [address]
        case 0x8D: regs16[i_reg] = i_ea; break;

        // MOV seg, rm16
        case 0x8E: regs16[REG_ES + (i_reg & 3)] = get_rm(1); break;

        // POP rm
        case 0x8F: i_tmp = pop(); put_rm(1, i_tmp); break;

        // XCHG AX, r16
        case 0x90: case 0x91: case 0x92: case 0x93:
        case 0x94: case 0x95: case 0x96: case 0x97: {

            i_reg = opcode_id & 7;
            i_tmp = regs16[REG_AX];
            regs16[REG_AX] = regs16[i_reg];
            regs16[i_reg]  = i_tmp;
            break;
        }

        // CBW, CWD
        case 0x98: regs  [REG_AH] = regs  [REG_AL] &   0x80 ?   0xFF :   0x00; break;
        case 0x99: regs16[REG_DX] = regs16[REG_AX] & 0x8000 ? 0xFFFF : 0x0000; break;

        // CALLF
        case 0x9A: {

            i_tmp  = fetch(2);
            i_tmp2 = fetch(2);

            push(regs16[REG_CS]);
            push(reg_ip);

            reg_ip = i_tmp;
            regs16[REG_CS] = i_tmp2;
            break;
        }

        // FWAIT
        case 0x9B: break;

        // PUSHF
        case 0x9C: push(get_flags()); break;

        // POPF
        case 0x9D: set_flags(pop()); break;

        // SAHF
        case 0x9E: {

            i_tmp   = regs[REG_AH];
            flags.c = !!(i_tmp & 0x01);
            flags.p = !!(i_tmp & 0x04);
            flags.a = !!(i_tmp & 0x10);
            flags.z = !!(i_tmp & 0x40);
            flags.s = !!(i_tmp & 0x80);
            break;
        }

        // LAHF
        case 0x9F: {

            regs[REG_AH] = (uint8_t) get_flags();
            break;
        }

        // MOV A, m16
        case 0xA0: regs[REG_AL]   = rd(SEGREG(segment_id, fetch(2)), 1); break;
        case 0xA1: regs16[REG_AX] = rd(SEGREG(segment_id, fetch(2)), 2); break;
        case 0xA2: wr(SEGREG(segment_id, fetch(2)), regs[REG_AL],    1); break;
        case 0xA3: wr(SEGREG(segment_id, fetch(2)), regs16[REG_AX],  2); break;

        // MOVSx
        case 0xA4: case 0xA5: {

            if (i_rep && regs16[REG_CX] == 0) break;

            i_size = opcode_id & 1;
            i_tmp  = rd(SEGREG(segment_id, regs16[REG_SI]), 1 + i_size);
            wr(SEGREG(REG_ES, regs16[REG_DI]), i_tmp, 1 + i_size);

            incsi(i_size);
            incdi(i_size);
            autorep(i_size, 0);
            break;
        }

        // CMPSx
        case 0xA6: case 0xA7: {

            if (i_rep && regs16[REG_CX] == 0) break;

            i_size = opcode_id & 1;
            i_op1  = rd(SEGREG(segment_id, regs16[REG_SI]), 1 + i_size);
            i_op2  = rd(SEGREG(REG_ES,     regs16[REG_DI]), 1 + i_size);
            arithlogic(ALU_SUB, i_size, i_op1, i_op2);

            incsi(i_size);
            incdi(i_size);
            autorep(i_size, 1);
            break;
        }

        // SCASx
        case 0xAE: case 0xAF: {

            if (i_rep && regs16[REG_CX] == 0) break;

            i_size = opcode_id & 1;
            i_op1  = regs16[REG_AX];
            i_op2  = rd(SEGREG(REG_ES, regs16[REG_DI]), 1 + i_size);
            arithlogic(ALU_SUB, i_size, i_op1, i_op2);

            incdi(i_size);
            autorep(i_size, 1);
            break;
        }

        // TEST A, i8
        case 0xA8: case 0xA9: {

            i_size = opcode_id & 1;
            i_op1  = i_size ? regs16[REG_AX] : regs[REG8(REG_AL)];
            i_op2  = fetch(1 + i_size);
            arithlogic(ALU_AND, i_size, i_op1, i_op2);
            break;
        }

        // STOSx
        case 0xAA: case 0xAB: {

            if (i_rep && regs16[REG_CX] == 0) break;

            i_size = opcode_id & 1;
            wr(SEGREG(REG_ES, regs16[REG_DI]), regs16[REG_AX], 1 + i_size);
            incdi(i_size);
            autorep(i_size, 0);
            break;
        }

        // LODSx
        case 0xAC: case 0xAD: {

            if (i_rep && regs16[REG_CX] == 0) break;

            i_size = opcode_id & 1;
            i_tmp  = rd(SEGREG(segment_id, regs16[REG_SI]), 2);
            if (i_size) regs16[REG_AX] = i_tmp; else regs[REG_AL] = i_tmp;

            incsi(i_size);
            autorep(i_size, 0);
            break;
        }

        // MOV r8, imm8
        case 0xB0: case 0xB1: case 0xB2: case 0xB3:
        case 0xB4: case 0xB5: case 0xB6: case 0xB7: {

            regs[ REG8(opcode_id) ] = fetch(1);
            break;
        }

        // MOV r16, imm16
        case 0xB8: case 0xB9: case 0xBA: case 0xBB:
        case 0xBC: case 0xBD: case 0xBE: case 0xBF: {

            regs16[ opcode_id & 7 ] = fetch(2);
            break;
        }

        // <SHIFT> rm, i8
        case 0xC0: case 0xC1: {

            i_size = opcode_id & 1;
            put_rm(i_size, shiftlogic(i_reg, i_size, get_rm(i_size), fetch(1)));
            break;
        }

        // RET, RET imm8
        case 0xC2: case 0xC3: {

            i_tmp  = pop();
            if (opcode_id == 0xC2) regs16[REG_SP] += fetch(2);
            reg_ip = i_tmp;
            break;
        }

        // LES, LDS r, rm
        case 0xC4: case 0xC5: {

            i_tmp = SEGREG(segment_id, i_ea);
            i_op1 = rd(i_tmp, 2);
            i_op2 = rd(i_tmp+2, 2);

            regs16[i_reg] = i_op1;
            regs16[opcode_id == 0xC4 ? REG_ES : REG_DS] = i_op2;
            break;
        }

        // MOV rm, i8/16
        case 0xC6: put_rm(0, fetch(1)); break;
        case 0xC7: put_rm(1, fetch(2)); break;

        // RETF [imm]
        case 0xCA:
        case 0xCB: {

            i_op1 = pop();
            i_op2 = pop();

            if (opcode_id == 0xCA) regs16[REG_SP] += fetch(2);

            reg_ip = i_op1;
            regs16[REG_CS] = i_op2;

            break;
        }

        // INT3, INT i8, INTO
        case 0xCC: interrupt(3); break;
        case 0xCD: interrupt(fetch(1)); break;
        case 0xCE: if (flags.o) interrupt(4); break;

        // IRET
        case 0xCF: {

            i_op1 = pop();
            i_op2 = pop();
            set_flags(pop());
            regs16[REG_CS] = i_op2;
            reg_ip = i_op1;
            break;
        }

        // <SHIFT> rm, 1|cl
        case 0xD0: case 0xD1: case 0xD2: case 0xD3: {

            i_size = opcode_id & 1;
            put_rm(i_size, shiftlogic(i_reg, i_size, get_rm(i_size), opcode_id & 2 ? regs[REG_CL] : 1));
            break;
        }

        // AAM
        case 0xD4: {

            i_tmp = fetch(1);
            if (i_tmp == 0) interrupt(0);
            else {
                regs[REG_AH]  = regs[REG_AL] / i_tmp;
                regs[REG_AL] %= i_tmp;
            }
            break;
        }

        // AAD
        case 0xD5: {

            i_tmp = fetch(1);
            regs[REG_AL] = regs[REG_AL] + i_tmp*regs[REG_AH];
            regs[REG_AH] = 0;
            break;
        }

        case 0xD6: { // SALC

            regs[REG_AL] = flags.c ? 0xFF : 0x00;
            break;
        }
        case 0xD7: { // XLAT

            regs[REG_AL] = rd(16*regs16[segment_id] + regs16[REG_BX] + regs[REG_AL], 1);
            break;
        }

        // LOOPxx b8
        case 0xE0:
        case 0xE1:
        case 0xE2: {

            i_tmp = (signed char) fetch(1);

            // Сперва CX уменьшается
            regs16[REG_CX]--;

            // Если CX <> 0, то можно выполнить переход
            if (regs16[REG_CX]) {

                if ((/* LOOPNZ */ opcode_id == 0xE0 && !flags.z) ||
                    (/* LOOPZ  */ opcode_id == 0xE1 &&  flags.z) ||
                    (/* LOOP   */ opcode_id == 0xE2))
                        reg_ip += i_tmp;
            }

            break;
        }

        // JCXZ short
        case 0xE3: i_tmp = (signed char) fetch(1); if (!regs16[REG_CX]) reg_ip += i_tmp; break;

        // IN
        case 0xE4: case 0xE5:
        case 0xEC: case 0xED: {

            i_tmp = opcode_id & 8 ? regs16[REG_DX] : fetch(1);
            regs[REG_AL] = port_in(i_tmp);
            if (opcode_id & 1) regs[REG_AH] = port_in(i_tmp);
            break;
        }

        // CALL near
        case 0xE8: {

            i_tmp = fetch(2);
            push(reg_ip);
            reg_ip += i_tmp;
            break;
        }

        // JMP near
        case 0xE9: i_tmp = fetch(2); reg_ip += i_tmp; break;

        // JMP far offset:segment
        case 0xEA: {

            i_tmp  = fetch(2);
            i_tmp2 = fetch(2);
            reg_ip = i_tmp;
            regs16[REG_CS] = i_tmp2;
            break;
        }

        // JMP short
        case 0xEB: i_tmp = fetch(1); reg_ip += (signed char) i_tmp; break;

        // OUT
        case 0xE6: case 0xE7:
        case 0xEE: case 0xEF: {

            i_tmp = opcode_id & 8 ? regs16[REG_DX] : fetch(1);
            port_out(i_tmp, regs[REG_AL]);
            if (opcode_id & 1) port_out(i_tmp, regs[REG_AH]);
            break;
        }

        // Trap Flag
        case 0xF1: interrupt(1); break;

        // Установка и сброс флагов
        case 0xF4: reg_ip--; is_halt = 1; break;   // HLT
        case 0xF5: flags.c = !flags.c; break; // CMC

        // Групповые арифметическо-логические с непосредственным операндом
        case 0xF6:
        case 0xF7: {

            switch (i_reg) {

                case 0:
                case 1: // TEST rm, i8

                    i_size = opcode_id & 1;
                    i_op1  = get_rm(i_size);
                    i_op2  = fetch(1 + i_size);
                    arithlogic(ALU_AND, i_size, i_op1, i_op2);
                    break;

                case 2: // NOT

                    i_size = opcode_id & 1;
                    put_rm(i_size, ~get_rm(i_size));
                    break;

                case 3: // NEG

                    i_size = opcode_id & 1;
                    put_rm(i_size, arithlogic(ALU_SUB, i_size, 0, get_rm(i_size)));
                    break;
            }

            break;
        }

        // Снятие и установка флагов
        case 0xF8: case 0xF9: flags.c = opcode_id & 1; break; // CLC | STC
        case 0xFA: case 0xFB: flags.i = opcode_id & 1; break; // CLI | STI
        case 0xFC: case 0xFD: flags.d = opcode_id & 1; break; // CLD | STD

        // Групповая инструкция #4
        case 0xFE: {

            switch (i_reg) {

                case 0: // INC rm8
                case 1: // DEC rm8

                    i_op1   = get_rm(0);
                    old_cf  = flags.c;
                    put_rm(0, arithlogic(i_reg ? ALU_SUB : ALU_ADD, 0, i_op1, 1));
                    flags.c = old_cf;
                    break;

                default:

                    ud_opcode(opcode_id);
            }

            break;
        }

        // Групповая инструкция #5
        case 0xFF: {

            switch (i_reg) {

                case 0: // INC rm8
                case 1: // DEC rm8

                    i_op1   = get_rm(1);
                    old_cf  = flags.c;
                    put_rm(1, arithlogic(i_reg ? ALU_SUB : ALU_ADD, 1, i_op1, 1));
                    flags.c = old_cf;
                    break;

                case 2: // CALL far

                    push(reg_ip);
                    reg_ip = get_rm(1);
                    break;

                case 3: // CALL far rm

                    i_tmp = SEGREG(segment_id, i_ea);

                    i_op1 = rd(i_tmp, 2);
                    i_op2 = rd(i_tmp + 2, 2);

                    push(regs16[REG_CS]);
                    push(reg_ip);

                    reg_ip = i_op1;
                    regs16[REG_CS] = i_op2;
                    break;

                // JMP r/m
                case 4: reg_ip = get_rm(1); break;

                // JMP far [bx] как пример
                case 5:

                    i_tmp  = SEGREG(segment_id, i_ea);
                    reg_ip = rd(i_tmp, 2);
                    regs16[REG_CS] = rd(i_tmp + 2, 2);
                    break;

                // PUSH rm
                case 6: push(get_rm(1)); break;

                default:

                    ud_opcode(opcode_id);
            }

            break;
        }

        // Jccc b16
        case 0x180: case 0x181: case 0x182: case 0x183:
        case 0x184: case 0x185: case 0x186: case 0x187:
        case 0x188: case 0x189: case 0x18A: case 0x18B:
        case 0x18C: case 0x18D: case 0x18E: case 0x18F: {

            i_tmp = fetch(2);
            if (cond(opcode_id & 15))
                reg_ip += i_tmp;

            break;
        }

        default: ud_opcode(opcode_id);
    }

    // Вызов Trap прерывания
    if (flags.i && flags.t) interrupt(1);

    // Вызов по таймеру
    if (flags.i) call_interrupt8();
}

int main(int argc, char* argv[]) {

    char in_start = 1;

    // Инициализация окна
    SDL_Init(SDL_INIT_VIDEO);
    sdl_screen = SDL_SetVideoMode(width = 2*640, height = 2*400, 32, SDL_HWSURFACE | SDL_DOUBLEBUF);
    SDL_EnableUNICODE(1);
    SDL_EnableKeyRepeat(500, 30);
    SDL_WM_SetCaption("Эмулятор 8086", 0);

    // Загрузка bios в память
    int bios_rom = open("bios.rom", 32898);
    if (bios_rom < 0) {
        bios_rom = argc > 1 ? open(argv[1], 32898) : -1;
        if (bios_rom < 0) { printf("No bios.rom present"); exit(1); }
    }
    (void) read(bios_rom, RAM + 0xF0100, 0xFF00);

    reset();

    // Цикл исполнения одной инструкции
    while (in_start) {

        // Проверить наличие нового события
        while (SDL_PollEvent(& sdl_event)) {
            switch (sdl_event.type) {
                case SDL_QUIT: in_start = 0; break;
            }
        }

        // Остановка на перерисовку и ожидание
        ftime(&ms_clock);

        // Вычисление разности времени
        int time_curr = ms_clock.millitm;
        int time_diff = time_curr - ms_prevtime;
        if (time_diff < 0) time_diff += 1000;

        // Если прошло 20 мс, выполнить инструкции, обновить экран
        if (time_diff >= 20) {

            ms_prevtime = time_curr;

            // Исполнение порции инструкции x 50
            for (int i = 0; i < 20000; i++) {
                step();
            }

            SDL_Flip(sdl_screen);
        }

        // Задержка исполнения
        SDL_Delay(1);
    }

    // memdump(0); memdump(0xF0100); regdump();

    SDL_Quit();
    return 0;
}
