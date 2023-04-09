rake example[4] >/dev/null || exit 1 # 2>/dev/null
echo LEVEL 0
./bin/cvm --entry=level1 --xverbose ./tmp/example_4/example_4_level0.dabcb 2>/dev/null
echo LEVEL 1
./bin/cvm --entry=level1 --xverbose ./tmp/example_4/example_4_level0.vm ./tmp/example_4/example_4_level1.dabcb 2>/dev/null
echo LEVEL 2
./bin/cvm --entry=level2 --xverbose ./tmp/example_4/example_4_level0.vm ./tmp/example_4/example_4_level1.vm ./tmp/example_4/example_4_level2.dabcb 2>/dev/null
