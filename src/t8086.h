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

// Машинное состояние
unsigned char   RAM[1024*1024+65536-16]; // 1mb + HiMem
unsigned char   regs[32];
unsigned short* regs16;
struct flags_struct flags;

int i_size;
int i_rep;
int opcode_id;
int segment_over_en;
int segment_id;
enum rep_prefix {
    REPNZ = 1,
    REPZ = 2,
};
