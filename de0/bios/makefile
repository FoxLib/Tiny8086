all:
	fasm bios.asm
	php ../dmif.php bios.bin > ../cyclone5/bios.mif
	../../8086sdl/t8086 bios.bin
