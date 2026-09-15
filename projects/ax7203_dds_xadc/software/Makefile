CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra -std=c11
all: pcie_capture
pcie_capture: pcie_capture.c
	$(CC) $(CFLAGS) -o $@ $<
clean:
	rm -f pcie_capture
.PHONY: all clean
