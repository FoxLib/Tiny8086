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

enum alu_name {

    ALU_ADD = 0,
    ALU_OR  = 1,
    ALU_ADC = 2,
    ALU_SBB = 3,
    ALU_AND = 4,
    ALU_SUB = 5,
    ALU_XOR = 6,
    ALU_CMP = 7
};

enum regs_name {

    // 16 bit
    REG_AX = 0, REG_CX = 1, REG_DX = 2, REG_BX = 3,
    REG_SP = 4, REG_BP = 5, REG_SI = 6, REG_DI = 7,

    // 8 bit
    REG_AL = 0, REG_CL = 2, REG_DL = 4, REG_BL = 6,
    REG_AH = 1, REG_CH = 3, REG_DH = 5, REG_BH = 7,

    // Segment
    REG_ES = 8, REG_CS = 9, REG_SS = 10, REG_DS = 11
};

#define REG8(x) ((x & 4) >> 2) | ((x & 3) << 1)
#define SEGREG(a,b) (16*regs16[a] + b)

// Машинное состояние
#define RAMTOP  (1024*1024+65536+256)  // 1mb + HiMem + Xlat
unsigned char   RAM[RAMTOP];
unsigned char   regs[32];
unsigned short* regs16;
unsigned short  reg_ip;
struct flags_struct flags;

int is_halt;
int i_size;
int i_rep;
int i_tmp, i_tmp2;
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

static const unsigned char font16[256][16] = {
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // 00
    {0x00, 0x00, 0x7e, 0x81, 0xa5, 0xa5, 0xa5, 0x81, 0x81, 0xbd, 0x99, 0x81, 0x7e, 0x00, 0x00, 0x00}, // 01
    {0x00, 0x00, 0x7e, 0xff, 0xdb, 0xdb, 0xdb, 0xff, 0xff, 0xc3, 0xe7, 0xff, 0x7e, 0x00, 0x00, 0x00}, // 02
    {0x00, 0x00, 0x6c, 0xfe, 0xfe, 0xfe, 0xfe, 0xfe, 0xfe, 0x7c, 0x38, 0x10, 0x00, 0x00, 0x00, 0x00}, // 03
    {0x00, 0x00, 0x00, 0x00, 0x10, 0x38, 0x7c, 0xfe, 0x7c, 0x38, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00}, // 04
    {0x00, 0x00, 0x00, 0x18, 0x3c, 0x3c, 0xe7, 0xe7, 0xe7, 0x18, 0x18, 0x3c, 0x00, 0x00, 0x00, 0x00}, // 05
    {0x00, 0x00, 0x00, 0x18, 0x3c, 0x7e, 0xff, 0xff, 0x7e, 0x18, 0x18, 0x3c, 0x00, 0x00, 0x00, 0x00}, // 06
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x3c, 0x3c, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // 07
    {0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xe7, 0xc3, 0xc3, 0xe7, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff}, // 08
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x3c, 0x66, 0x42, 0x42, 0x66, 0x3c, 0x00, 0x00, 0x00, 0x00, 0x00}, // 09
    {0xff, 0xff, 0xff, 0xff, 0xc3, 0x99, 0xbd, 0xbd, 0x99, 0xc3, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff}, // 0A
    {0x00, 0x00, 0x00, 0x1e, 0x0e, 0x1a, 0x32, 0x78, 0xcc, 0xcc, 0xcc, 0x78, 0x00, 0x00, 0x00, 0x00}, // 0B
    {0x00, 0x00, 0x00, 0x3c, 0x66, 0x66, 0x66, 0x3c, 0x18, 0x7e, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00}, // 0C
    {0x00, 0x00, 0x00, 0x3f, 0x33, 0x3f, 0x30, 0x30, 0x30, 0x70, 0xf0, 0xe0, 0x00, 0x00, 0x00, 0x00}, // 0D
    {0x00, 0x00, 0x00, 0x7f, 0x63, 0x7f, 0x63, 0x63, 0x63, 0x67, 0xe7, 0xe6, 0xc0, 0x00, 0x00, 0x00}, // 0E
    {0x00, 0x00, 0x00, 0x18, 0x18, 0xdb, 0x3c, 0xe7, 0x3c, 0xdb, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00}, // 0F
    {0x00, 0x00, 0x00, 0x80, 0xc0, 0xe0, 0xf8, 0xfe, 0xf8, 0xe0, 0xc0, 0x80, 0x00, 0x00, 0x00, 0x00}, // 10
    {0x00, 0x00, 0x00, 0x02, 0x06, 0x0e, 0x3e, 0xfe, 0x3e, 0x0e, 0x06, 0x02, 0x00, 0x00, 0x00, 0x00}, // 11
    {0x00, 0x00, 0x00, 0x18, 0x3c, 0x7e, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7e, 0x3c, 0x18, 0x00}, // 12
    {0x00, 0x00, 0x00, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x00, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00}, // 13
    {0x00, 0x00, 0x00, 0x7f, 0xdb, 0xdb, 0xdb, 0x7b, 0x1b, 0x1b, 0x1b, 0x1b, 0x00, 0x00, 0x00, 0x00}, // 14
    {0x00, 0x00, 0x7c, 0xc6, 0x60, 0x38, 0x6c, 0xc6, 0xc6, 0x6c, 0x38, 0x0c, 0xc6, 0x7c, 0x00, 0x00}, // 15
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xfe, 0xfe, 0xfe, 0x00, 0x00, 0x00, 0x00}, // 16
    {0x00, 0x00, 0x00, 0x18, 0x3c, 0x7e, 0x18, 0x18, 0x18, 0x7e, 0x3c, 0x18, 0x7e, 0x00, 0x00, 0x00}, // 17
    {0x00, 0x00, 0x00, 0x18, 0x3c, 0x7e, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00}, // 18
    {0x00, 0x00, 0x00, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7e, 0x3c, 0x18, 0x00}, // 19
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x0c, 0xfe, 0x0c, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // 1A
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x60, 0xfe, 0x60, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // 1B
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc0, 0xc0, 0xc0, 0xfe, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // 1C
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x28, 0x6c, 0xfe, 0x6c, 0x28, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // 1D
    {0x00, 0x00, 0x00, 0x00, 0x10, 0x38, 0x38, 0x7c, 0x7c, 0xfe, 0xfe, 0x00, 0x00, 0x00, 0x00, 0x00}, // 1E
    {0x00, 0x00, 0x00, 0xfe, 0x7c, 0x38, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // 1F
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // 20
    {0x00, 0x00, 0x18, 0x3c, 0x3c, 0x3c, 0x3c, 0x18, 0x18, 0x18, 0x00, 0x00, 0x18, 0x00, 0x00, 0x00}, // 21
    {0x00, 0x66, 0x66, 0x66, 0x66, 0x66, 0x24, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // 22
    {0x00, 0x00, 0x6c, 0x6c, 0x6c, 0xfe, 0x6c, 0x6c, 0x6c, 0xfe, 0x6c, 0x6c, 0x6c, 0x00, 0x00, 0x00}, // 23
    {0x18, 0x18, 0x18, 0x7c, 0xc6, 0xc2, 0xc0, 0x7c, 0x06, 0x86, 0xc6, 0x7c, 0x18, 0x18, 0x18, 0x00}, // 24
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xc2, 0xc6, 0x0c, 0x18, 0x30, 0x66, 0xc6, 0x00, 0x00, 0x00, 0x00}, // 25
    {0x00, 0x00, 0x38, 0x6c, 0x6c, 0x6c, 0x38, 0x76, 0xdc, 0xcc, 0xcc, 0xcc, 0x76, 0x00, 0x00, 0x00}, // 26
    {0x00, 0x30, 0x30, 0x30, 0x30, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // 27
    {0x00, 0x00, 0x0c, 0x18, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x18, 0x0c, 0x00, 0x00, 0x00}, // 28
    {0x00, 0x00, 0x30, 0x18, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x18, 0x30, 0x00, 0x00, 0x00}, // 29
    {0x00, 0x00, 0x00, 0x00, 0x66, 0x66, 0x3c, 0xff, 0x3c, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00}, // 2A
    {0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x18, 0x7e, 0x18, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00}, // 2B
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x18, 0x18, 0x30, 0x00, 0x00}, // 2C
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xfe, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // 2D
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00}, // 2E
    {0x00, 0x00, 0x00, 0x02, 0x06, 0x0c, 0x18, 0x30, 0x60, 0xc0, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00}, // 2F
    {0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xce, 0xde, 0xf6, 0xf6, 0xe6, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 30
    {0x00, 0x00, 0x18, 0x18, 0x38, 0x78, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7e, 0x00, 0x00, 0x00}, // 31
    {0x00, 0x00, 0x7c, 0xc6, 0xc6, 0x06, 0x06, 0x0c, 0x18, 0x30, 0x60, 0xc6, 0xfe, 0x00, 0x00, 0x00}, // 32
    {0x00, 0x00, 0x7c, 0xc6, 0x06, 0x06, 0x06, 0x3c, 0x06, 0x06, 0x06, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 33
    {0x00, 0x00, 0x0c, 0x1c, 0x3c, 0x6c, 0xcc, 0xcc, 0xfe, 0x0c, 0x0c, 0x0c, 0x1e, 0x00, 0x00, 0x00}, // 34
    {0x00, 0x00, 0xfe, 0xc0, 0xc0, 0xc0, 0xfc, 0x06, 0x06, 0x06, 0x06, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 35
    {0x00, 0x00, 0x38, 0x60, 0xc0, 0xc0, 0xfc, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 36
    {0x00, 0x00, 0xfe, 0xc6, 0xc6, 0x06, 0x06, 0x0c, 0x18, 0x30, 0x30, 0x30, 0x30, 0x00, 0x00, 0x00}, // 37
    {0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xc6, 0xc6, 0x7c, 0xc6, 0xc6, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 38
    {0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x7e, 0x06, 0x06, 0x0c, 0x78, 0x00, 0x00, 0x00}, // 39
    {0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00}, // 3A
    {0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x18, 0x18, 0x30, 0x00, 0x00}, // 3B
    {0x00, 0x00, 0x00, 0x06, 0x0c, 0x18, 0x30, 0x60, 0x30, 0x18, 0x0c, 0x06, 0x00, 0x00, 0x00, 0x00}, // 3C
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7e, 0x00, 0x00, 0x7e, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // 3D
    {0x00, 0x00, 0x00, 0x60, 0x30, 0x18, 0x0c, 0x06, 0x0c, 0x18, 0x30, 0x60, 0x00, 0x00, 0x00, 0x00}, // 3E
    {0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xc6, 0x0c, 0x18, 0x18, 0x18, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00}, // 3F
    {0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xc6, 0xde, 0xde, 0xde, 0xdc, 0xc0, 0xc0, 0x7c, 0x00, 0x00, 0x00}, // 40
    {0x00, 0x00, 0x10, 0x38, 0x6c, 0xc6, 0xc6, 0xc6, 0xfe, 0xc6, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // 41
    {0x00, 0x00, 0xfc, 0x66, 0x66, 0x66, 0x66, 0x7c, 0x66, 0x66, 0x66, 0x66, 0xfc, 0x00, 0x00, 0x00}, // 42
    {0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xc0, 0xc0, 0xc0, 0xc0, 0xc6, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 43
    {0x00, 0x00, 0xfc, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0xfc, 0x00, 0x00, 0x00}, // 44
    {0x00, 0x00, 0xfe, 0x66, 0x62, 0x60, 0x68, 0x78, 0x68, 0x68, 0x62, 0x66, 0xfe, 0x00, 0x00, 0x00}, // 45
    {0x00, 0x00, 0xfe, 0x66, 0x62, 0x60, 0x68, 0x78, 0x68, 0x68, 0x60, 0x60, 0xf0, 0x00, 0x00, 0x00}, // 46
    {0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xc0, 0xc0, 0xc0, 0xde, 0xc6, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 47
    {0x00, 0x00, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xfe, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // 48
    {0x00, 0x00, 0x3c, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3c, 0x00, 0x00, 0x00}, // 49
    {0x00, 0x00, 0x1e, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0xcc, 0xcc, 0x78, 0x00, 0x00, 0x00}, // 4A
    {0x00, 0x00, 0xe6, 0x66, 0x66, 0x6c, 0x6c, 0x78, 0x6c, 0x6c, 0x66, 0x66, 0xe6, 0x00, 0x00, 0x00}, // 4B
    {0x00, 0x00, 0xf0, 0x60, 0x60, 0x60, 0x60, 0x60, 0x60, 0x60, 0x62, 0x66, 0xfe, 0x00, 0x00, 0x00}, // 4C
    {0x00, 0x00, 0xc6, 0xc6, 0xee, 0xfe, 0xfe, 0xd6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // 4D
    {0x00, 0x00, 0xc6, 0xc6, 0xe6, 0xf6, 0xfe, 0xde, 0xce, 0xc6, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // 4E
    {0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 4F
    {0x00, 0x00, 0xfc, 0x66, 0x66, 0x66, 0x66, 0x66, 0x7c, 0x60, 0x60, 0x60, 0xf0, 0x00, 0x00, 0x00}, // 50
    {0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xd6, 0xde, 0x7c, 0x0c, 0x00, 0x00, 0x00}, // 51
    {0x00, 0x00, 0xfc, 0x66, 0x66, 0x66, 0x66, 0x7c, 0x6c, 0x66, 0x66, 0x66, 0xe6, 0x00, 0x00, 0x00}, // 52
    {0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xc6, 0x60, 0x38, 0x0c, 0xc6, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 53
    {0x00, 0x00, 0x7e, 0x7e, 0x5a, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3c, 0x00, 0x00, 0x00}, // 54
    {0x00, 0x00, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 55
    {0x00, 0x00, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x6c, 0x38, 0x10, 0x00, 0x00, 0x00}, // 56
    {0x00, 0x00, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xd6, 0xd6, 0xfe, 0x7c, 0x6c, 0x6c, 0x00, 0x00, 0x00}, // 57
    {0x00, 0x00, 0xc6, 0xc6, 0xc6, 0x6c, 0x38, 0x38, 0x38, 0x6c, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // 58
    {0x00, 0x00, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3c, 0x18, 0x18, 0x18, 0x18, 0x3c, 0x00, 0x00, 0x00}, // 59
    {0x00, 0x00, 0xfe, 0xc6, 0xc6, 0x8c, 0x18, 0x30, 0x60, 0xc2, 0xc6, 0xc6, 0xfe, 0x00, 0x00, 0x00}, // 5A
    {0x00, 0x00, 0x3c, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x3c, 0x00, 0x00, 0x00}, // 5B
    {0x00, 0x00, 0x00, 0x80, 0xc0, 0xe0, 0x70, 0x38, 0x1c, 0x0e, 0x06, 0x02, 0x00, 0x00, 0x00, 0x00}, // 5C
    {0x00, 0x00, 0x3c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x3c, 0x00, 0x00, 0x00}, // 5D
    {0x10, 0x10, 0x38, 0x6c, 0xc6, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // 5E
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x00}, // 5F
    {0x30, 0x30, 0x30, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // 60
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x78, 0xcc, 0x0c, 0x7c, 0xcc, 0xcc, 0xcc, 0x76, 0x00, 0x00, 0x00}, // 61
    {0x00, 0x00, 0xe0, 0x60, 0x60, 0x60, 0x78, 0x6c, 0x66, 0x66, 0x66, 0x66, 0x7c, 0x00, 0x00, 0x00}, // 62
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xc0, 0xc0, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 63
    {0x00, 0x00, 0x1c, 0x0c, 0x0c, 0x0c, 0x3c, 0x6c, 0xcc, 0xcc, 0xcc, 0xcc, 0x76, 0x00, 0x00, 0x00}, // 64
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xfe, 0xc0, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 65
    {0x00, 0x00, 0x38, 0x6c, 0x64, 0x60, 0xf0, 0x60, 0x60, 0x60, 0x60, 0x60, 0xf0, 0x00, 0x00, 0x00}, // 66
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x76, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0x7c, 0x0c, 0xcc, 0x78, 0x00}, // 67
    {0x00, 0x00, 0xe0, 0x60, 0x60, 0x6c, 0x76, 0x66, 0x66, 0x66, 0x66, 0x66, 0xe6, 0x00, 0x00, 0x00}, // 68
    {0x00, 0x00, 0x18, 0x18, 0x00, 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3c, 0x00, 0x00, 0x00}, // 69
    {0x00, 0x00, 0x06, 0x06, 0x00, 0x0e, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x66, 0x66, 0x3c, 0x00}, // 6A
    {0x00, 0x00, 0xe0, 0x60, 0x60, 0x66, 0x66, 0x6c, 0x78, 0x6c, 0x66, 0x66, 0xe6, 0x00, 0x00, 0x00}, // 6B
    {0x00, 0x00, 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3c, 0x00, 0x00, 0x00}, // 6C
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xec, 0xfe, 0xd6, 0xd6, 0xd6, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // 6D
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xdc, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x00, 0x00, 0x00}, // 6E
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 6F
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xdc, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x7c, 0x60, 0xf0, 0x00}, // 70
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x76, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0x7c, 0x0c, 0x1e, 0x00}, // 71
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xdc, 0x76, 0x66, 0x60, 0x60, 0x60, 0x60, 0xf0, 0x00, 0x00, 0x00}, // 72
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x7c, 0xc6, 0xc6, 0x70, 0x1c, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 73
    {0x00, 0x00, 0x10, 0x30, 0x30, 0xfc, 0x30, 0x30, 0x30, 0x30, 0x30, 0x36, 0x1c, 0x00, 0x00, 0x00}, // 74
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0x76, 0x00, 0x00, 0x00}, // 75
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3c, 0x18, 0x00, 0x00, 0x00}, // 76
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xc6, 0xc6, 0xc6, 0xd6, 0xd6, 0xfe, 0x6c, 0x6c, 0x00, 0x00, 0x00}, // 77
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xc6, 0xc6, 0x6c, 0x38, 0x38, 0x6c, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // 78
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x7e, 0x06, 0x0c, 0xf8, 0x00}, // 79
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xfe, 0xc6, 0xcc, 0x18, 0x30, 0x66, 0xc6, 0xfe, 0x00, 0x00, 0x00}, // 7A
    {0x00, 0x0e, 0x18, 0x18, 0x18, 0x18, 0x18, 0x70, 0x70, 0x18, 0x18, 0x18, 0x18, 0x18, 0x0e, 0x00}, // 7B
    {0x00, 0x00, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x00, 0x00}, // 7C
    {0x00, 0x70, 0x18, 0x18, 0x18, 0x18, 0x18, 0x0e, 0x0e, 0x18, 0x18, 0x18, 0x18, 0x18, 0x70, 0x00}, // 7D
    {0x00, 0x00, 0x76, 0xdc, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // 7E
    {0x00, 0x00, 0x00, 0x00, 0x10, 0x38, 0x6c, 0xc6, 0xc6, 0xc6, 0xc6, 0xfe, 0x00, 0x00, 0x00, 0x00}, // 7F
    {0x00, 0x00, 0x10, 0x38, 0x6c, 0xc6, 0xc6, 0xc6, 0xfe, 0xc6, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // 80
    {0x00, 0x00, 0xfe, 0x66, 0x62, 0x60, 0x7c, 0x66, 0x66, 0x66, 0x66, 0x66, 0xfc, 0x00, 0x00, 0x00}, // 81
    {0x00, 0x00, 0xfc, 0x66, 0x66, 0x66, 0x7c, 0x66, 0x66, 0x66, 0x66, 0x66, 0xfc, 0x00, 0x00, 0x00}, // 82
    {0x00, 0x00, 0xfe, 0x66, 0x62, 0x60, 0x60, 0x60, 0x60, 0x60, 0x60, 0x60, 0xf0, 0x00, 0x00, 0x00}, // 83
    {0x00, 0x00, 0x3e, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0xff, 0xc3, 0xc3, 0x00}, // 84
    {0x00, 0x00, 0xfe, 0x66, 0x66, 0x62, 0x68, 0x78, 0x68, 0x62, 0x66, 0x66, 0xfe, 0x00, 0x00, 0x00}, // 85
    {0x00, 0x00, 0xd6, 0xd6, 0xd6, 0x7c, 0x38, 0x7c, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0x00, 0x00, 0x00}, // 86
    {0x00, 0x00, 0x7c, 0xc6, 0x06, 0x06, 0x06, 0x3c, 0x06, 0x06, 0x06, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 87
    {0x00, 0x00, 0xc6, 0xc6, 0xce, 0xde, 0xfe, 0xf6, 0xe6, 0xc6, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // 88
    {0x38, 0x38, 0xc6, 0xc6, 0xce, 0xde, 0xfe, 0xf6, 0xe6, 0xc6, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // 89
    {0x00, 0x00, 0xe6, 0x66, 0x6c, 0x6c, 0x78, 0x6c, 0x6c, 0x66, 0x66, 0x66, 0xe6, 0x00, 0x00, 0x00}, // 8A
    {0x00, 0x00, 0x3e, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0xe6, 0x00, 0x00, 0x00}, // 8B
    {0x00, 0x00, 0xc6, 0xee, 0xfe, 0xfe, 0xd6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // 8C
    {0x00, 0x00, 0xc6, 0xc6, 0xc6, 0xc6, 0xfe, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // 8D
    {0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 8E
    {0x00, 0x00, 0xfe, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // 8F
    {0x00, 0x00, 0xfc, 0x66, 0x66, 0x66, 0x66, 0x66, 0x7c, 0x60, 0x60, 0x60, 0xf0, 0x00, 0x00, 0x00}, // 90
    {0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xc0, 0xc0, 0xc0, 0xc0, 0xc6, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 91
    {0x00, 0x00, 0x7e, 0x7e, 0x5a, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3c, 0x00, 0x00, 0x00}, // 92
    {0x00, 0x00, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x7e, 0x06, 0x06, 0x06, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // 93
    {0x00, 0x00, 0x18, 0x7e, 0xdb, 0xdb, 0xdb, 0xdb, 0xdb, 0xdb, 0xdb, 0x7e, 0x18, 0x00, 0x00, 0x00}, // 94
    {0x00, 0x00, 0xc6, 0xc6, 0xc6, 0x6c, 0x38, 0x38, 0x38, 0x6c, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // 95
    {0x00, 0x00, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xfe, 0x06, 0x06, 0x00}, // 96
    {0x00, 0x00, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x7e, 0x06, 0x06, 0x06, 0x06, 0x00, 0x00, 0x00}, // 97
    {0x00, 0x00, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xfe, 0x00, 0x00, 0x00}, // 98
    {0x00, 0x00, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xfe, 0x03, 0x03, 0x00}, // 99
    {0x00, 0x00, 0xf8, 0xf0, 0xb0, 0x30, 0x3c, 0x36, 0x36, 0x36, 0x36, 0x36, 0x7c, 0x00, 0x00, 0x00}, // 9A
    {0x00, 0x00, 0xc6, 0xc6, 0xc6, 0xc6, 0xf6, 0xde, 0xde, 0xde, 0xde, 0xde, 0xf6, 0x00, 0x00, 0x00}, // 9B
    {0x00, 0x00, 0xf0, 0x60, 0x60, 0x60, 0x7c, 0x66, 0x66, 0x66, 0x66, 0x66, 0xfc, 0x00, 0x00, 0x00}, // 9C
    {0x00, 0x00, 0x78, 0xcc, 0x86, 0x86, 0x26, 0x3e, 0x26, 0x86, 0x86, 0xcc, 0x78, 0x00, 0x00, 0x00}, // 9D
    {0x00, 0x00, 0x9c, 0xb6, 0xb6, 0xb6, 0xb6, 0xf6, 0xb6, 0xb6, 0xb6, 0xb6, 0x9c, 0x00, 0x00, 0x00}, // 9E
    {0x00, 0x00, 0x7e, 0xcc, 0xcc, 0xcc, 0xcc, 0x7c, 0x6c, 0xcc, 0xcc, 0xce, 0xce, 0x00, 0x00, 0x00}, // 9F
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x78, 0xcc, 0x0c, 0x7c, 0xcc, 0xcc, 0xcc, 0x76, 0x00, 0x00, 0x00}, // A0
    {0x00, 0x00, 0x00, 0x1c, 0x30, 0x60, 0x7c, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3c, 0x00, 0x00, 0x00}, // A1
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xfc, 0x66, 0x66, 0x7c, 0x66, 0x66, 0x66, 0xfc, 0x00, 0x00, 0x00}, // A2
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xfe, 0x62, 0x60, 0x60, 0x60, 0x60, 0x60, 0xf0, 0x00, 0x00, 0x00}, // A3
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x3e, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0xff, 0xc3, 0xc3, 0x00}, // A4
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xfe, 0xc0, 0xc0, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // A5
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xd6, 0xd6, 0xd6, 0x7c, 0x7c, 0xd6, 0xd6, 0xd6, 0x00, 0x00, 0x00}, // A6
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x3c, 0x66, 0x66, 0x0c, 0x06, 0x66, 0x66, 0x3c, 0x00, 0x00, 0x00}, // A7
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xc6, 0xce, 0xde, 0xfe, 0xf6, 0xe6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // A8
    {0x00, 0x00, 0x38, 0x38, 0x00, 0xc6, 0xce, 0xde, 0xfe, 0xf6, 0xe6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // A9
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xe6, 0x66, 0x6c, 0x78, 0x6c, 0x66, 0x66, 0xe6, 0x00, 0x00, 0x00}, // AA
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x3e, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0xe6, 0x00, 0x00, 0x00}, // AB
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xc6, 0xee, 0xfe, 0xfe, 0xd6, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // AC
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xc6, 0xc6, 0xc6, 0xfe, 0xc6, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // AD
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // AE
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xfe, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // AF
    {0x44, 0x11, 0x44, 0x11, 0x44, 0x11, 0x44, 0x11, 0x44, 0x11, 0x44, 0x11, 0x44, 0x11, 0x44, 0x11}, // B0
    {0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55}, // B1
    {0x77, 0xdd, 0x77, 0xdd, 0x77, 0xdd, 0x77, 0xdd, 0x77, 0xdd, 0x77, 0xdd, 0x77, 0xdd, 0x77, 0xdd}, // B2
    {0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18}, // B3
    {0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0xf8, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18}, // B4
    {0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0xf8, 0x18, 0xf8, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18}, // B5
    {0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0xf6, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36}, // B6
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xfe, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36}, // B7
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf8, 0x18, 0xf8, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18}, // B8
    {0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0xf6, 0x06, 0xf6, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36}, // B9
    {0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36}, // BA
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xfe, 0x06, 0xf6, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36}, // BB
    {0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0xf6, 0x06, 0xfe, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // BC
    {0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0xfe, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // BD
    {0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0xf8, 0x18, 0xf8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // BE
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf8, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18}, // BF
    {0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x1f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // C0
    {0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // C1
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18}, // C2
    {0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x1f, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18}, // C3
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // C4
    {0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0xff, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18}, // C5
    {0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x1f, 0x18, 0x1f, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18}, // C6
    {0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x37, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36}, // C7
    {0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x37, 0x30, 0x3f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // C8
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3f, 0x30, 0x37, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36}, // C9
    {0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0xf7, 0x00, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // CA
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x00, 0xf7, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36}, // CB
    {0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x37, 0x30, 0x37, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36}, // CC
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x00, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // CD
    {0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0xf7, 0x00, 0xf7, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36}, // CE
    {0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0xff, 0x00, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // CF
    {0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // D0
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x00, 0xff, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18}, // D1
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36}, // D2
    {0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x3f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // D3
    {0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x1f, 0x18, 0x1f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // D4
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1f, 0x18, 0x1f, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18}, // D5
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3f, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36}, // D6
    {0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0xff, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36, 0x36}, // D7
    {0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0xff, 0x18, 0xff, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18}, // D8
    {0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0xf8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // D9
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1f, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18}, // DA
    {0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff}, // DB
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff}, // DC
    {0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0}, // DD
    {0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f, 0x0f}, // DE
    {0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // DF
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xdc, 0x66, 0x66, 0x66, 0x66, 0x66, 0x7c, 0x60, 0x60, 0xf0, 0x00}, // E0
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x7c, 0xc6, 0xc6, 0xc0, 0xc0, 0xc6, 0xc6, 0x7c, 0x00, 0x00, 0x00}, // E1
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x7e, 0x5a, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3c, 0x00, 0x00, 0x00}, // E2
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0xc6, 0x7e, 0x06, 0x0c, 0xf8, 0x00}, // E3
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x7e, 0xdb, 0xdb, 0xdb, 0xdb, 0xdb, 0x7e, 0x18, 0x18, 0x00}, // E4
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xc6, 0xc6, 0x6c, 0x38, 0x38, 0x6c, 0xc6, 0xc6, 0x00, 0x00, 0x00}, // E5
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xfe, 0x06, 0x06, 0x00}, // E6
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xc6, 0xc6, 0xc6, 0xc6, 0x7e, 0x06, 0x06, 0x06, 0x00, 0x00, 0x00}, // E7
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xfe, 0x00, 0x00, 0x00}, // E8
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xfe, 0x03, 0x03, 0x00}, // E9
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xf8, 0xb0, 0x3c, 0x36, 0x36, 0x36, 0x36, 0x7c, 0x00, 0x00, 0x00}, // EA
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xc6, 0xc6, 0xf6, 0xde, 0xde, 0xde, 0xde, 0xf6, 0x00, 0x00, 0x00}, // EB
    {0x00, 0x00, 0x00, 0x00, 0x00, 0xf0, 0x60, 0x60, 0x7c, 0x66, 0x66, 0x66, 0xfc, 0x00, 0x00, 0x00}, // EC
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x3c, 0x66, 0x06, 0x1e, 0x06, 0x66, 0x66, 0x3c, 0x00, 0x00, 0x00}, // ED
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x9c, 0xb6, 0xb6, 0xf6, 0xb6, 0xb6, 0xb6, 0x9c, 0x00, 0x00, 0x00}, // EE
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x7e, 0xcc, 0xcc, 0xcc, 0x7c, 0x6c, 0xcc, 0xce, 0x00, 0x00, 0x00}, // EF
    {0x00, 0x00, 0x00, 0x00, 0xfe, 0x00, 0x00, 0xfe, 0x00, 0x00, 0xfe, 0x00, 0x00, 0x00, 0x00, 0x00}, // F0
    {0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x7e, 0x18, 0x18, 0x00, 0x00, 0xff, 0x00, 0x00, 0x00, 0x00}, // F1
    {0x00, 0x00, 0x00, 0x30, 0x18, 0x0c, 0x06, 0x0c, 0x18, 0x30, 0x00, 0x7e, 0x00, 0x00, 0x00, 0x00}, // F2
    {0x00, 0x00, 0x00, 0x0c, 0x18, 0x30, 0x60, 0x30, 0x18, 0x0c, 0x00, 0x7e, 0x00, 0x00, 0x00, 0x00}, // F3
    {0x00, 0x00, 0x00, 0x0e, 0x1b, 0x1b, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18}, // F4
    {0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0xd8, 0xd8, 0x70, 0x00, 0x00, 0x00, 0x00}, // F5
    {0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x7e, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00}, // F6
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x76, 0xdc, 0x00, 0x76, 0xdc, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // F7
    {0x00, 0x38, 0x6c, 0x6c, 0x6c, 0x38, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // F8
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // F9
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // FA
    {0x00, 0x0f, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0xec, 0x6c, 0x3c, 0x1c, 0x0c, 0x00, 0x00, 0x00, 0x00}, // FB
    {0x00, 0x00, 0xd8, 0x6c, 0x6c, 0x6c, 0x6c, 0x6c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // FC
    {0x00, 0x00, 0x70, 0xd8, 0x30, 0x60, 0xc8, 0xf8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // FD
    {0x00, 0x00, 0x00, 0x00, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x00, 0x00, 0x00, 0x00}, // FE
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}  // FF
};
