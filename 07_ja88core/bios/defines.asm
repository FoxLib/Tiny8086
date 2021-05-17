; 4AC sd_arg
; 4B0 sd_type (0=none,1,2,3=sdhc)

SD_CMD_ARG              equ     $4AC
SD_TYPE                 equ     $4B0
SD_LBA                  equ     $4B1

; Константы для SD-обработчика
R1_READY_STATE          equ     0x00
R1_ILLEGAL_COMMAND      equ     0x04
SD_CARD_TYPE_NONE       equ     0x00
SD_CARD_TYPE_SD1        equ     0x01
SD_CARD_TYPE_SD2        equ     0x02
SD_CARD_TYPE_SD3        equ     0x03
