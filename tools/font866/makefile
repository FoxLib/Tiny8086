SDL=`sdl-config --cflags --libs`
all:
	g++ $(SDL) -I/home/fox/dev/programs/includes -O3 main.cc -Wno-unused-result -lSDL -o main
	./main
	mv cgamem.mif ../../de0/cyclone5/cgamem.mif