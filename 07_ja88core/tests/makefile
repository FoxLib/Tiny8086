all: 14_add.o
	rm *.o
%.o: %.s
	as $< -o $@
	objcopy -O binary --only-section=.text $@ $<.bin
