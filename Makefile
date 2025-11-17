CXX = g++
CXXFLAGS = -O2 -Wall

TARGET = gen_qkv_mem
SRC = gen_qkv_mem.cpp

MEM_FILES = Q.mem K.mem V.mem

all: run

$(TARGET): tb/$(SRC)
	$(CXX) $(CXXFLAGS) -o tb/$(TARGET) tb/$(SRC)

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f tb/$(TARGET) output/$(MEM_FILES)