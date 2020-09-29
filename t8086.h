SDL_Surface *   sdl_screen;
SDL_Event       sdl_event;
struct timeb    ms_clock;
int             ms_prevtime;
int             width;
int             height;

struct flags_struct {
    unsigned char o; // 11 overflow
    unsigned char d; // 10 direction
    unsigned char i; //  9 interrupt
    unsigned char t; //  8 trap
    unsigned char s; //  7 sign
    unsigned char z; //  6 zero
    unsigned char a; //  4 aux
    unsigned char p; //  2 parity
    unsigned char c; //  0 carry
};

enum regs_name {

    // 16 bit
    REG_AX = 0, REG_CX = 1, REG_DX = 2, REG_BX = 3,
    REG_SP = 4, REG_BP = 5, REG_SI = 6, REG_DI = 7,

    // 8 bit
    REG_AL = 0, REG_CL = 2, REG_DL = 4, REG_BL = 6,
    REG_AH = 1, REG_CH = 3, REG_DH = 5, REG_BH = 7,

    // Segment
    REG_ES = 8, REG_CS = 9, REG_SS = 10, REG_DS = 11,

    // System
    REG_IP = 12
};

#define REG8(x) ((x & 4) >> 2) | ((x & 3) << 1)
#define SEGREG(a,b) (16*regs16[a] + b)

// Машинное состояние
unsigned char   RAM[1024*1024+65536-256]; // 1mb + HiMem + Xlat
unsigned char   regs[32];
unsigned short* regs16;
struct flags_struct flags;

int i_size;
int i_rep;
int i_tmp;
int opcode_id;
int segment_over_en;
int segment_id;

unsigned short i_ea;
int i_modrm, i_mod, i_reg, i_rm;

enum rep_prefix {
    REPNZ = 1,
    REPZ  = 2,
};

// Карта наличия байта MODRM
static const unsigned char opcodemap_modrm[512] = {

    // Базовый опкод
    1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, /* 00 */
    1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, /* 10 */
    1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, /* 20 */
    1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, /* 30 */
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, /* 40 */
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, /* 50 */
    0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, /* 60 */
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, /* 70 */
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, /* 80 */
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, /* 90 */
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, /* A0 */
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, /* B0 */
    1, 1, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, /* C0 */
    1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, /* D0 */
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, /* E0 */
    0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, /* F0 */

    // Расширенный опкод
    1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, /* 100 */
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, /* 110 */
    1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 1, 1, 1, /* 120 */
    0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, /* 130 */
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, /* 140 */
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, /* 150 */
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, /* 160 */
    1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1, /* 170 */
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, /* 180 */
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, /* 190 */
    0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, /* 1A0 */
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, /* 1B0 */
    1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, /* 1C0 */
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, /* 1D0 */
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, /* 1E0 */
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, /* 1F0 */
};
