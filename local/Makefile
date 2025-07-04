CC = gcc
CXX = g++

CFLAGS ?= -march=native -ggdb3 -O2
CXXFLAGS ?= -march=native -ggdb3 -O2

override CFLAGS := -Wall -Wextra -std=c17 $(CFLAGS)
override CXXFLAGS := -Wall -Wextra -std=c++20 $(CXXFLAGS)
override LDFLAGS := -Wl,-O1,--relax,--sort-common,--as-needed,-z,relro,-z,now,-z,pack-relative-relocs $(LDFLAGS)

all: \
	autofsync.so \
	renameat2 \
	usbreset \
	# EOL

extra: \
	all \
	gpioke \
	# EOL

autofsync.so: override LDFLAGS += -Wl,--unresolved-symbols=report-all
autofsync.so: override LDLIBS += -ldl -pthread
gpioke: override LDLIBS += -lpci

%.so: %.c
	$(CC) $(CFLAGS) $(LDFLAGS) -fPIC -shared -o $@ $^ $(LDLIBS)
