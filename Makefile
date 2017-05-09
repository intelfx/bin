DESTDIR ?= $(HOME)/bin

CC = clang
CXX = clang++
RUSTC = rustc

override CFLAGS := -g -Wall -Wextra -std=c99 -DLOCAL $(CFLAGS)
override CXXFLAGS := -g -Wall -Wextra -std=c++14 $(CXXFLAGS)
override LDFLAGS := -rdynamic -Wl,-O1,--relax,-z,relro,--sort-common $(LDFLAGS)
override LDLIBS := -ldl -lm -lrt -lpthread $(LDLIBS)

install-%: %
	install -m755 $< $(DESTDIR)

%: %.asm
	nasm -f elf32 $< -o $@.o
	$(CC) -m32 $(LDFLAGS) $@.o $(LDLIBS) -o $@

%: %.rs
	$(RUSTC) $< -o $@
