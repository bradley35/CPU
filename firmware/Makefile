# Toolchain
CC      := riscv64-unknown-elf-gcc
LD      := $(CC)
OBJCOPY := riscv64-unknown-elf-objcopy

OBJDUMP       ?= riscv64-unknown-elf-objdump
DISASM_ARCH   ?= riscv:rv64
DISASM_ENDIAN ?= -EL
BASE          ?= 0x0

MEMORY_CHUNKS := 1

CHUNK_INDICES := $(shell seq 0 $$(( $(MEMORY_CHUNKS) - 1 )))
CHUNKFILES    := $(addprefix $(BUILD)/c,$(addsuffix .chunk,$(CHUNK_INDICES)))

# Arch/ABI + bare-metal friendly flags
CFLAGS  := -Wall -O2 -march=rv64i_zifencei -mabi=lp64 \
           -ffreestanding -fno-builtin -MMD -MP -ffixed-x10
# If you use inline asm or want stricter codegen, consider also: -fno-exceptions -fno-rtti (for C++)

# Linker script
LDSCRIPT := linker_script.ld

# Bare-metal link flags: no crt, use libc; use your script; also emit a map file
LDFLAGS := -nostartfiles -nostdlib -Wl,-T,$(LDSCRIPT)
LDFLAGS := -nostartfiles -nostdlib -Wl,-T,$(LDSCRIPT),--gc-sections

LIBS := -lgcc

# Project structure
BUILD := build
SRCS  := main.c
OBJS  := $(SRCS:%.c=$(BUILD)/%.o)
DEPS  := $(OBJS:.o=.d)

# Default: compile only (no link)
compile: $(BUILD)/app.bin

# Generate final bin (and elf)
app: $(CHUNKFILES)

$(CHUNKFILES): $(BUILD)/.chunks.stamp

$(BUILD)/.chunks.stamp: $(BUILD)/app.bin | $(BUILD)
	./bin_seperator/bin_seperator.rs $(BUILD)/app.bin $(MEMORY_CHUNKS) $(BUILD)
	@touch $@

# Link rule
$(BUILD)/app.elf: $(OBJS) $(LDSCRIPT) | $(BUILD)
	$(LD) $(OBJS) $(STARTUP) $(LDFLAGS) $(LIBS) -o $@
# Output flat binary
$(BUILD)/app.bin: $(BUILD)/app.elf
	$(OBJCOPY) -O binary $< $@

# Compile C -> .o (no linking)
$(BUILD)/%.o: %.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

# Ensure build dir exists
$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/app.dump: $(BUILD)/app.bin
	$(OBJDUMP) -D -b binary -m $(DISASM_ARCH) $(DISASM_ENDIAN) -M numeric --adjust-vma=$(BASE) $< > $@

disasm: $(BUILD)/app.dump

clean:
	rm -rf $(BUILD)

.PHONY: all app clean disasm

# Auto header deps (safe if missing on first run)
-include $(DEPS)





