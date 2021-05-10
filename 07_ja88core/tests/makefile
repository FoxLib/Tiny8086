all: 01_jmpmov.o 14_add.o
	rm *.o
%.o: %.s
	as $< -o $@
	objcopy -O binary --only-section=.text $@ $<.bin
test:
	php ../bios/bin2hex.php 01_jmpmov.s.bin > ../bios.hex
