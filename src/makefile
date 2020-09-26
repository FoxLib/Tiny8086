OPTS_ALL=-O3 -fsigned-char -std=c99
OPTS_SDL=`sdl-config --cflags --libs`

all: t8086
	./t8086
t8086: t8086.c
	${CC} t8086.c ${OPTS_SDL} ${OPTS_ALL} -o t8086
	strip t8086

clean:
	rm t8086
