all:
	nasm -f bin doom.asm -l doom.lst -o doom.bin
	dd if=doom.bin of=memory.bin bs=1 seek=31744
	php ../../utils/bin2mif.php memory.bin 262144 > ../../de0/memory.mif
	mv memory.bin ../../em
	cd ../../em && ./machine88
