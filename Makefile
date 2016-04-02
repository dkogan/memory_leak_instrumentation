SOURCES := $(wildcard *.c *.cpp *.cc)
OBJECTS := $(addsuffix .o,$(basename $(SOURCES)))

# if any -O... is requested, use that; otherwise, do -O3
FLAGS_OPTIMIZATION := $(if $(filter -O%,$(CFLAGS) $(CXXFLAGS) $(CPPFLAGS)),,-O3 -ffast-math)
CPPFLAGS := -MMD -g $(FLAGS_OPTIMIZATION) -Wall -Wextra -Wno-missing-field-initializers -Wno-unused-parameter
CFLAGS += -std=gnu11
CXXFLAGS += -std=gnu++11

LDLIBS := -ldl -lunwind -lbacktrace

all: alloc_hook.so

%.so: %.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ -fpic -shared $^ $(LDLIBS)

clean:
	rm -rf *.o *.d *.so

.PHONY: clean

-include *.d
