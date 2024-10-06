all: main.cpp rpg1.dat
	g++ -std=c++11 -O2 main.cpp -o cube -lsfml-window -lsfml-system -lsfml-graphics -lpng

format:
	clang-format -i main.cpp

run: all
	./cube

rpg1.dat: rpg1_dump.json map.rb
	ruby map.rb > rpg1.dat
