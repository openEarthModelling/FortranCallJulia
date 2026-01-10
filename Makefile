# Makefile for Fortran-Julia Middleware

# Detect Julia paths
JL_SHARE = $(shell julia -e 'print(joinpath(Sys.BINDIR, Base.DATAROOTDIR, "julia"))')
JULIA_CONFIG = $(JL_SHARE)/julia-config.jl

# Flags
CFLAGS   = -g -O2 -fPIC $(shell $(JULIA_CONFIG) --cflags)
LDFLAGS  = $(shell $(JULIA_CONFIG) --ldflags)
LDLIBS   = $(shell $(JULIA_CONFIG) --ldlibs)

# Compilers
CC = gcc
FC = gfortran
FFLAGS = -g -O2 -fno-underscoring

# Targets
TARGET = test_app
OBJS = bridge.o julia_sdk.o main.o

all: $(TARGET)

$(TARGET): $(OBJS)
	$(FC) -o $@ $(OBJS) $(LDFLAGS) $(LDLIBS) -lstdc++

bridge.o: bridge.c bridge.h
	$(CC) $(CFLAGS) -c bridge.c -o bridge.o

julia_sdk.o: julia_sdk.f90
	$(FC) $(FFLAGS) -c julia_sdk.f90 -o julia_sdk.o

main.o: main.f90 julia_sdk.o
	$(FC) $(FFLAGS) -c main.f90 -o main.o

clean:
	rm -f *.o *.mod $(TARGET)

.PHONY: all clean
