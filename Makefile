# Compiler and flags
CC = gcc
AS = as
CFLAGS = -O0 -march=rv64imafdc
ASFLAGS = -g -march=rv64imafdc
# ASFLAGS = -g

# Directories
SRC_DIR = src
BUILD_DIR = build

# Source and target files
SRC_FILES = $(wildcard $(SRC_DIR)/*.s)
OBJ_FILES = $(patsubst $(SRC_DIR)/%.s,$(BUILD_DIR)/%.o,$(SRC_FILES))
TARGET = sneaky

all: $(TARGET)

# Ensure build dir exists
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)


# Depend on it when building objects
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.s $(SRC_DIR)/sneaky.h | $(BUILD_DIR)
	$(AS) -I$(SRC_DIR) $(ASFLAGS) -o $@ $<

$(TARGET): $(OBJ_FILES)
	$(CC) $(CFLAGS) -static -o $@ $^

clean:
	find . -name '*~' -type f -delete
	rm -f $(TARGET) $(OBJ_FILES)

indent:
	@for f in $(SRC_FILES); do \
		echo "Indenting $$f"; \
		python3 indent.py --inplace $$f; \
	done
