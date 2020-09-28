OPTS_ALL=-O3 -fsigned-char -std=c99 -Wno-unused-result
OPTS_SDL=`sdl-config --cflags --libs`

all: t8086
	./t8086
t8086: t8086.c t8086.h helpers.c
	${CC} t8086.c ${OPTS_SDL} ${OPTS_ALL} -o t8086
	strip t8086

clean:
	rm t8086
