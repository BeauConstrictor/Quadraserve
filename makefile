NIM = nim
NIM_OPTS = -d:ssl

SRC_DIR = src/protocols
BIN_DIR = bin

NIM_SRCS := $(wildcard $(SRC_DIR)/*.nim)
BINS := $(patsubst $(SRC_DIR)/%.nim, $(BIN_DIR)/%, $(NIM_SRCS))

all: $(BIN_DIR) $(BINS)

$(BIN_DIR)/%: $(SRC_DIR)/%.nim
	$(NIM) c $(NIM_OPTS) -o:$@ $<

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

clean:
	rm -rf $(BIN_DIR)/*

.PHONY: all clean
