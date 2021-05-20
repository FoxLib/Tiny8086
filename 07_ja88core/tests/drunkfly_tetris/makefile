all:
	fasm tetris.asm
	dd if=tetris.com of=memory.bin bs=1 seek=31744
	php ../../utils/bin2mif.php memory.bin 262144 > ../../de0/memory.mif
	mv tetris.com ~/dosbox
	mv memory.bin ../../em
	cd ../../em && ./machine88
