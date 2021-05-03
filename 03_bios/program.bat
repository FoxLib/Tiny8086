fasm bios.asm

rem dd if=/dev/random of=rom.bin bs=1 count=32768
rem dd if=/dev/zero of=rom.bin bs=1 count=16384
rem dd if=../resources/font8x8.bin of=rom.bin bs=1 skip=256 seek=15616
rem dd if=zout/unit.cim of=rom.bin bs=1

mode com8 baud=460800 data=8

rem com7/8 ?
copy bios.bin /b com8 

rem pause