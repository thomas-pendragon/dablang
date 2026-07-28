# Audyt techniczno-strategiczny Dab

## Werdykt

Dab jest dziś rozbudowanym, historycznie interesującym prototypem języka: ma prawdziwy kompilator, assembler, własny format bytecode, VM, narzędzia i działający w podstawowych przypadkach mechanizm Rings, ale nie jest gotowym językiem ogólnego przeznaczenia. Najcenniejszym aktywem jest spójny pionowy demonstrator od źródła do wykonania oraz eksperyment z utrwalaniem skutków metaprogramowania między warstwami kompilacji. Największym problemem jest różnica między obiecaną semantyką a kodem: dokumentowany model `Type`, `Type?`, `Type!`, null-safety, szeroka inferencja i generyki nie istnieją w deklarowanej postaci. Obecny `master` nie buduje się bez korekt środowiska na współczesnym Linuksie, a po obejściu pierwszej blokady ujawnia awarię Rings, porażkę RSpec i build przykładów przekraczający 35-sekundowy limit, którego harness sam nie egzekwuje. VM i FFI zawierają potwierdzone błędy czasu życia, niezabezpieczone odczyty formatu binarnego i liczne ścieżki `assert`/`exit`, więc uruchamianie niezaufanego bytecode jest obecnie niebezpieczne. Warto rozwijać projekt tylko jako zawężone laboratorium staged metaprogramming i warstwowej VM, po uprzednim ustaleniu wykonywalnego kontraktu Dab 0.1 i zabezpieczeniu runtime. Główny kierunek powinien zachować istniejący pionowy pipeline oraz Rings, ale zamrozić ekspansję składni i bez dowodu nie obiecywać produktywności Ruby połączonej z kontrolą C++. Wariantem zapasowym jest konserwacja i archiwizacja jako dobrze odtwarzalnego projektu edukacyjnego. Zdecydowanie nie należy teraz przepisywać całości, dodawać kolejnych cech języka ani optymalizować VM przed uzyskaniem deterministycznego buildu, bezpieczeństwa pamięci i testów kontraktowych.

## 1. Executive summary

**Rekomendacja:** scenariusz D — radykalne zawężenie do eksperymentalnej platformy „Rings / staged metaprogramming over a small bytecode VM”, z bramką po Fazie 2. Dopiero udane, powtarzalne flagowe demo i udokumentowana semantyka mogą uzasadnić dalszą modernizację istniejącego Dab. Scenariusz B, czyli próba doprowadzenia obecnej całości do używalności ogólnej, ma zbyt duży koszt i zbyt mało zweryfikowanego popytu.

Najważniejsze ustalenia:

1. **[Fakt] Istnieje pełny pionowy system.** Ruby parsuje wiele plików, buduje i wielokrotnie przekształca mutowalny AST/IR, emituje tekstowy assembler, a assembler zapisuje sekcyjny format DAB v3 wykonywany przez interpreter C++; działają też disassembler, formatter, coverage, debugger i częściowy decompiler (`src/compiler/parts/main.rb:19-184`, `src/compiler/nodes/node_unit.rb:174-288`, `src/tobinary/tobinary.rb:188-403`, `src/cvm/main.cpp:504-972`).
2. **[Fakt] Rings są rzeczywistą implementacją, nie tylko dokumentem.** Kompilator czyta wcześniejsze obrazy jako stuby, VM może zapisać swój zmieniony obraz, a `frontend_multidab` przekazuje go jako podstawę następnej warstwy (`src/compiler/parts/readbin.rb:1-202`, `src/frontend/frontend_multidab.rb:27-72`, `src/cvm/bin_save.cpp`). Aktywne fixture’y pokrywają kilka warstw, dynamiczne klasy i metody.
3. **[Fakt] Najważniejsze deklaracje typów są fałszywe dla obecnego kodu.** Parser przyjmuje tylko pojedynczy identyfikator typu, `DabType.parse` rozpoznaje zamkniętą listę builtinów, a każdy zwykły typ przyjmuje `Nil`; nie ma parsera ani semantyki `?` i `!` (`src/compiler/parts/context.rb:133-139`, `src/compiler/parts/types.rb:2-25`, `README.md:21-29`, `TODO.md:5,40`).
4. **[Fakt] Specjalizacja istnieje, lecz jest wąska.** `ConcreteifyCall` klonuje tylko globalną funkcję o argumentach `Object`, gdy każde wywołanie ma co najmniej jeden konkretny argument; nie jest to ogólna inferencja ani stabilny system monomorfizacji (`src/compiler/processors/concreteify_call.rb:1-23`, `src/compiler/nodes/node_function.rb:259-274`).
5. **[Fakt] Czysty build nie przechodzi w zbadanym środowisku.** Repo wymaga niezainstalowanego Ruby 3.1.6; po dostarczeniu Rubiego, Bundlera i Premake beta2 GCC 15 zatrzymuje `-Werror=format-truncation` w `src/cdisasm/disasm.cpp:363`, a Clang 21 wykrywa dangling pointer w `src/cvm/main.cpp:1092`.
6. **[Fakt] Duża liczba fixture’ów nie oznacza zielonego stanu.** Po środowiskowym wyłączeniu jednej kategorii `-Werror` przechodzą setki podstawowych przypadków, ale `multidab` abortuje w `0002_multilevel.test`, RSpec ma jedną porażkę i 16 pending, a build przykładów nie egzekwuje własnego timeoutu.
7. **[Fakt] Runtime nie ma granicy zaufania.** Loader ufa długościom i adresom z `.dabcb`, używa type-punning i asercji zamiast walidacji; FFI ładuje arbitralne biblioteki i symbole, a kilka konwersji tworzy dangling pointers lub nieograniczone odczyty (`src/cshared/stream.h:215-222`, `src/cvm/bin_load.cpp:3-305`, `src/cvm/main.cpp:1088-1131`, `src/cvm/syscalls.cpp:52-122`).
8. **[Mocna przesłanka] Efektywny bus factor wynosi jeden.** Z 2492 commitów `master` 2487 przypada na dwie tożsamości najpewniej tej samej osoby; brak release tags, a ostatni commit `master` to `6bd3197` z 2024-10-08.
9. **[Mocna przesłanka] Najbardziej wiarygodna wartość jest badawcza i edukacyjna.** Istniejący kod pokazuje wiele faz kompilatora i nietypową serializację stanu VM, ale skala braków semantycznych, bezpieczeństwa, bibliotek i narzędzi wyklucza dziś wiarygodne pozycjonowanie produktowe.
10. **[Hipoteza do sprawdzenia] Rings mogą być wartościowym wyróżnikiem**, jeśli mały demonstrator wykaże deterministyczność, hermetyczność, poprawną invalidację i lepszą widoczność wygenerowanych API niż prostszy build-time codegen.

## 2. Poziom pewności audytu i ograniczenia

### 2.1 Zakres i metoda

Audyt wykonano 2026-07-28 na `master`:

```text
commit: 6bd31971f4264cb30b0719dddfba55dee62889da
data:   2024-10-08T22:54:41+02:00
opis:   x86_64 only for mac
```

`git ls-remote origin refs/heads/master` wskazał ten sam SHA. Przejrzano strukturę wszystkich 825 śledzonych plików (47 686 linii według `git ls-files | xargs wc -l`), dokumentację, build, CI, Ruby compiler/frontend, wszystkie narzędzia natywne, stdlib, przykłady, testy i historię 2492 commitów. Uruchomienia wykonano w izolowanym checkoutcie pod `/tmp`, aby nie zmieniać źródeł; jedynym artefaktem w głównym repozytorium jest wymagany raport.

Zastosowane etykiety:

- **[Fakt]** — bezpośrednio potwierdzony kodem, historią albo wynikiem polecenia.
- **[Mocna przesłanka]** — najbardziej prawdopodobny wniosek z kilku zgodnych dowodów.
- **[Hipoteza]** — sensowna możliwość wymagająca eksperymentu.
- **[Niezweryfikowane]** — brak środowiska lub dowodu pozwalającego rozstrzygnąć.

### 2.2 Poziom pewności

| Obszar | Pewność | Dlaczego |
|---|---|---|
| Architektura, format i fazy kompilacji | wysoka | śledzenie source-to-execution, wygenerowane ABI i aktywne test frontends |
| Semantyka typów, parsera, klas i Rings | wysoka | kod implementacji, testy pozytywne/negatywne i sprzeczności z dokumentacją |
| Build i testy na Linux x86_64 | wysoka | powtórzone uruchomienia GCC 15, Clang 21, Ruby 3.3 oraz izolowany checkout |
| Bezpieczeństwo pamięci i odporność loadera | wysoka dla wskazanych błędów, średnia dla pełnego wpływu | potwierdzone ścieżki kodu; nie wykonywano weaponized exploitów |
| macOS i Windows | niska | przeanalizowano konfigurację, ale nie uruchomiono tych platform |
| Wydajność i skalowanie | niska–średnia | dwie mikrospecy kompilatora; brak reprezentatywnych benchmarków runtime |
| Popyt użytkowników i szanse adopcji | średnia–niska | repo ma minimalny ślad publiczny, ale nie wykonano badań rynku ani wywiadów |

### 2.3 Ograniczenia

- **[Niezweryfikowane]** Nie wykonano builda na macOS ani Windows; twierdzenia platformowe wynikają z konfiguracji, TODO i kodu warunkowego.
- **[Niezweryfikowane]** Nie przeprowadzono fuzzingu ani uruchomień ASan/UBSan/MSan; lista błędów natywnych jest dolną granicą, nie pełnym spisem.
- **[Niezweryfikowane]** Nie mierzono czasu dużych programów ani jakości wygenerowanego kodu; „wydajność” z README pozostaje ambicją.
- **[Fakt]** Oficjalny workflow GitHub Actions istnieje, lecz publiczna strona workflow pokazywała zero uruchomień; nie ma zatem historycznego zielonego SHA do porównania.
- **[Fakt]** `origin/c_export` zawiera niepołączony eksperyment embeddingu/callbacków, ale oceny funkcji dotyczą wyłącznie `master`.
- **[Fakt]** Nie modyfikowano kodu i nie próbowano naprawiać problemów; obejście flagi kompilatora było wyłącznie eksperymentem środowiskowym.

### 2.4 Historia, aktywność i ownership

`master` ma 2492 commity, zero merge commits i zero tags. Rozkład po **committer date** — uczciwszy dla aktywności niż author date zaległych Dependabot commits — wynosi:

| Okres | Commity |
|---|---:|
| 2017 | 1889 |
| 2018 | 209 |
| 2019 | 1 |
| 2020 | 1 |
| 2021–2022 | 0 |
| marzec–kwiecień 2023 | 313 |
| 2024: maj / wrzesień / październik | 1 / 8 / 70 |

`master` kończy się 2024-10-08; najpóźniejszy commit na jakimkolwiek zbadanym remote ref jest na `origin/c_export` z 2024-10-09. Model aktywności to zatem intensywny rozwój prototypu, długa przerwa i dwa krótkie powroty, nie ciągłe maintenance.

`git shortlog -sne HEAD`:

```text
2100  Thomas Pendragon <root@thomaspendragon.com>
 387  Tomasz Pędraszewski <t.pedraszewski@28byteslater.com>
   4  dependabot[bot]
   1  thomas-pendragon
```

**[Mocna przesłanka]** Dwie główne tożsamości należą do jednej osoby, więc efektywny bus factor wynosi 1. Ten ownership dominuje także hotspoty: `src/compiler` ma 957 historycznych touches (832 starej + 125 nowej tożsamości), `src/cvm` 809 (702 + 107), a `src/cshared` 269 (237 + 32). Najczęściej zmieniany `src/cvm/main.cpp` ma 436 file touches, co wzmacnia ocenę ryzyka tego modułu.

Archeologia gałęzi:

- `origin/c_export`: 25 ahead / 0 behind `master`, +436/−14 w 22 plikach; dodaje C embedding/callback/function literals, lecz pozostaje niepołączonym jednodniowym eksperymentem.
- `origin/orm-example`: 21 ahead / 79 behind; osobna próba ORM/ARC z 2023 roku.
- `origin/__call`: 1 ahead / 166 behind; `origin/webserver-upgrade`: 1 ahead / 346 behind.

**Wniosek:** gałęzie są dowodem eksploracji, nie obecnej funkcjonalności produktu. Brak merges/tags i bardzo skrótowe commit subjects osłabiają możliwość odtworzenia intencji zmian, mimo bogatej historii kodu.

## 3. Mapa architektury

### 3.1 Inwentarz i odpowiedzialności

| Ścieżka | Rola | Charakterystyka |
|---|---|---|
| `src/compiler/` | parser kontekstowy, AST/IR, semantyka, SSA, optymalizacje, lowering, emisja assemblera | Ruby; 8162 linii; silnie mutowalny model node |
| `src/shared/` | scanner/parser primitives, definicje opcode/class, harness i wspólne narzędzia | źródło prawdy dla generatorów Ruby/C++ |
| `src/frontend/` | CLI kompilatora, assemblera, VM, debuggera, Rings i test frontends | orchestration i golden comparison |
| `src/tobinary/` | assembler `.dabca` → `.dabcb` | Ruby; etykiety, skoki, sekcje |
| `src/cvm/` | loader, interpreter, runtime values, builtiny, debugger, FFI, snapshot Rings | C++; największy hotspot |
| `src/cshared/` | struktury binarne, stream/buffer, wygenerowane opcode/class headers | wspólne ABI narzędzi natywnych |
| `src/cdisasm/` | disassembler bytecode | C++ |
| `src/cdumpcov/`, `src/cov/` | odczyt i agregacja coverage | C++ + Ruby |
| `src/decompile/` | częściowy decompiler assemblera do AST/źródła | Ruby |
| `src/format/` | parser + `formatted_source` | Ruby; nie zachowuje pełnej semantyki |
| `stdlib/` | Ring standard library | 11 plików, 286 linii Dab; reszta builtinów w C++ |
| `test/` | fixture’y end-to-end i goldeny | 480 plików, wiele osobnych frontendów |
| `spec/` | RSpec dla elementów Ruby | 24 pliki; poza domyślnym `rake` |
| `tasks/` | generowanie opcode, nagłówków, FFI i dokumentacji | część buildu i ABI |
| `examples/` | Snake/SDL, webserver, database | demonstratory stare, zależne od hosta |
| `docs/` | Jekyll: design, build i generowane klasy/opcode | większość designu z 2017 roku |

### 3.2 Diagram source-to-execution

```text
 pliki .dab                              wcześniejsze Ring .dabcb/.vm
     |                                               |
     v                                               v
 DabProgramStream / character scanner       DabBinReader::parse_ring
 src/shared/parser.rb                       stuby klas/funkcji/symboli
     |                                               |
     +------------------------+----------------------+
                              v
                 DabContext, recursive descent
                 src/compiler/parts/context.rb
                              |
                              v
                mutowalny DabNodeUnit (AST + IR)
                              |
       init -> checks -> SSA -> optimize -> lower -> post-SSA
                 -> late lower -> flatten, do punktu stałego
                              |
                              v
                    DabOutput: tekst .dabca
                              |
                              v
       Ruby assembler: etykiety + fixup skoków + sekcje DAB v3
                              |
                              v
                       binarne .dabcb
                   /          |          \
                  v           v           v
             cdisasm      decompiler   cdumpcov
                  \           |           /
                   \          |          /
                              v
               DabVM: loader sekcji -> dispatch opcode
                    |                       |
                    v                       v
              wynik / coverage        `dumpvm` snapshot
                                            |
                                            v
                                      następny Ring

 stdlib/*.dab -> ten sam pipeline -> tmp/stdlib.dabcb -> --ring-base
 formatter    -> parser -> AST.formatted_source przed semantyką/loweringiem
 generators   -> src/shared/opcodes.rb/classes.rb -> nagłówki C++ + docs
```

### 3.3 Przepływ kompilatora

1. **Wejście i wcześniejsze Rings.** `DabCompilerFrontend#run` ładuje każde `ring_base` przez `DabBinReader` i scala stuby w jeden `DabNodeUnit` (`src/compiler/parts/main.rb:19-38`).
2. **Skanowanie i parsing.** `DabProgramStream` przechowuje tekst i pozycje; `DabContext` wykonuje recursive descent z backtrackingiem, bez osobnego token streamu (`src/shared/parser.rb:21-111,136-486`, `src/compiler/parts/context.rb:52-71`).
3. **Wspólne drzewo.** Około 70 klas `DabNode` reprezentuje źródłowy AST, informacje scope/type, SSA/rejestry, formatowanie i późniejszy codegen (`src/compiler/nodes/node.rb:4-323`).
4. **Fazy.** 17 kategorii callbacków rejestruje się metaprogramowaniem klas Ruby (`src/compiler/parts/module_processors.rb:1-102`). Init, sprawdzenia, SSA, optymalizacje, lowering i flattening biegną iteracyjnie do punktu stałego (`src/compiler/parts/main.rb:83-150,230-272`).
5. **Specjalizacja.** Nowe wyspecjalizowane funkcje mogą pojawić się podczas faz, dlatego pętla ponownie przetwarza nowo utworzone funkcje (`src/compiler/parts/main.rb:131-150`).
6. **Emisja.** `DabNodeUnit#compile_new` sortuje funkcje/klasy, emituje kod oraz sekcje `data`, `code`, `clas`, `symd`, `symb`, `fext`, `ndat` i opcjonalne coverage (`src/compiler/nodes/node_unit.rb:174-284`).
7. **Assembler.** `src/tobinary/tobinary.rb:316-403` tłumaczy pseudo-opcode nagłówka, zapisuje operand bytes i poprawia względne skoki; wynik zaczyna się od `DAB\0`, wersji i tablicy sekcji (`:188-233`).
8. **Wykonanie.** `DabVM` wczytuje i scala sekcje, tworzy tablice klas/funkcji/symboli, po czym `execute_single` interpretuje rejestrowe opcode (`src/cvm/bin_load.cpp:3-305`, `src/cvm/main.cpp:504-972`).

### 3.4 Role języków i reprezentacji

- **Ruby** odpowiada za składnię, większość semantyki, transformacje, assembler, formatter, decompiler, coverage report, generatory i test harness. To skracało eksperymentowanie, ale globalne zmienne `$debug`, `$opt`, `$strip`, `$entry`, `$with_cov` i dynamiczne rejestry faz utrudniają reentrancy oraz analizę zależności (`src/compiler/parts/main.rb:40-56`).
- **C++** odpowiada za ładowanie bytecode, interpreter, obiekty runtime, builtiny, FFI, debug i zapis obrazu VM. `src/cvm/main.cpp` łączy singleton VM, dispatch, casty i CLI; nie ma bezpiecznej granicy między wejściem binarnym a runtime.
- **C** nie jest osobnym backendem; projekt używa C ABI, `dlopen`/`dlsym` i funkcji testowych, ale runtime jest C++.
- **IR/bytecode.** Nie ma stabilnego typowanego IR. Mutowalny AST przechodzi przez SSA/register lowering, a publicznym punktem sprzężenia staje się tekstowy assembler i host-zależny częściowo format binarny. Realne opcode obejmują load/move, skoki, calls, syscalls, retain/release, cast, instvar, coverage, blocks/boxes i classvars (`src/shared/opcodes.rb:20-129`).

### 3.5 Standard library, FFI, testy i generowanie

- **Stdlib:** `Rakefile:184-188` kompiluje wszystkie `stdlib/*.dab` do `tmp/stdlib.dabcb`, który jest Ring base dla programów. API jest hybrydowe: metody wysokopoziomowe w Dab opierają się na klasach i funkcjach w `src/cvm/default_classes.cpp` oraz `defaults*.cpp`.
- **FFI:** `__dlimport` przekazuje bibliotekę i symbol do `kernel_dlimport`; POSIX używa `dlopen`/`dlsym`, a wygenerowany `ffi_signatures.h` mapuje skończony zestaw sygnatur na rzutowane wskaźniki funkcji (`src/cvm/syscalls.cpp:52-122`, `tasks/ffi_signatures.rb:6-38`). Windows pozostaje niezaimplementowany (`TODO.md:10`).
- **Testy:** `Rakefile:190-236` buduje zadania z katalogów fixture’ów; frontendy uruchamiają kompilator/assembler/VM i porównują tekstowe goldeny. `Rakefile:250-251` nazywa `spec` wyłącznie aliasem testów Dab — nie uruchamia RSpec.
- **Generowanie:** definicje w `src/shared/opcodes.rb` i `classes.rb` generują nagłówki C++, docs i debug tables; osobny generator produkuje wielką drabinę FFI (`Rakefile:128-141,255-265`). Daje to jedno logiczne źródło, ale wygenerowane artefakty są śledzone i muszą pozostawać zsynchronizowane.

### 3.6 Najważniejsze sprzężenia i hotspoty

| Hotspot | Dlaczego zmiana jest ryzykowna |
|---|---|
| `src/compiler/parts/context.rb` | około 956 linii łączy gramatykę, scope state, rozpoznawanie klas i tworzenie AST |
| `src/compiler/nodes/node.rb` + `module_processors.rb` | jeden mutowalny graf skupia ownership, cache, source spans, diagnostykę, SSA, format i codegen |
| `src/compiler/parts/main.rb` | globalny stan i fixed-point pipeline zależny od kolejności callbacków |
| `src/shared/opcodes.rb` + generowane headers + assembler + VM + disassembler | jedna zmiana opcode wymaga zgodności kilku implementacji i narzędzi |
| `tobinary.rb`, `readbin.rb`, `stream.h`, `bin_load.cpp`, `bin_save.cpp` | layout formatu jest kodowany niezależnie w Ruby i C++ |
| `src/compiler/parts/types.rb`, `shared/classes.rb`, `cvm.h`, builtiny, FFI | model typów nie ma jednego formalnego kontraktu |
| `src/cvm/main.cpp` | globalny `$VM`, interpreter, casty, dispatch i CLI w około 1530 liniach |
| `src/cvm/define_method.cpp` | drugi, ręczny generator bytecode dla Rings, niezależny od codegenu Ruby |
| formatter i decompiler | odtwarzają tylko podzbiór semantyki AST/ABI i łatwo milcząco tracą informację |

## 4. Stan funkcji języka

Skala: **0** brak; **1** eksperymentalny szkic; **2** częściowa implementacja; **3** działa w podstawowych przypadkach; **4** solidnie przetestowane; **5** potencjalnie produkcyjne. Ocena 4 nie oznacza, że cały system jest bezpieczny — tylko że dany komponent ma szerokie potwierdzenie w granicach prototypu.

| Obszar | Ocena | Stan i uzasadnienie |
|---|---:|---|
| Lexer/scanner | 3 | **[Fakt]** Ręczny scanner obsługuje komentarze, strings, liczby, identyfikatory i source positions (`src/shared/parser.rb:21-52,136-477`). Nie ma token streamu; mapowanie linii jest per znak, a dedykowane specy parsera obejmują tylko trzy przypadki komentarzy. |
| Parser | 3 | **[Fakt]** Szeroka gramatyka recursive descent jest pośrednio ćwiczona przez 240 fixture’ów (`context.rb:101-942`). Brak recovery; EOF i część błędów wychodzą jako surowe wyjątki, a nie diagnostyka. |
| AST / IR | 4 | **[Fakt]** Około 70 node types, ownership, traversal, source spans, cache, SSA i codegen są realne; cache ma specy (`node.rb:4-323`, `spec/compiler/cache_spec.rb:5-31`). Minus: jeden mutowalny model pełni zbyt wiele ról. |
| Analiza semantyczna | 3 | **[Fakt]** Procesory sprawdzają istnienie funkcji/metod, arity, przypisania, return types i skoki. Katalog ma tylko 10 kontrolowanych kodów błędów (`parts/exceptions.rb:1-122`), a liczne host exceptions omijają ten model. |
| System typów | 2 | **[Fakt]** `DabType.parse` zna głównie builtiny, a member API jest hardkodowane (`parts/types.rb:2-20,39-135`). Branch `ByteBuffer` tworzy niezdefiniowane `DabTypeByteBuffer` — to jedyne wystąpienie nazwy w repo. Brak nominalnych typów klas użytkownika, poprawnego subtypowania i nullability. |
| Inferencja typów | 2 | **[Fakt]** Literały i część SSA propagują concrete types, lecz argumenty/lokale bez adnotacji zaczynają jako `Object`; brak constraint solvera, unions i inferencji międzyproceduralnej. Dokumentowane „compiler will deduct types” jest zawyżone (`README.md:21`). |
| Typowanie opcjonalne | 2 | **[Fakt]** Adnotacje builtinów przy zmiennych, argumentach i wynikach wykrywają część niezgodności (`test/dab/0025*`, `0026*`, `0164*`, `0165*`). `Type?` i źródłowe `Type!` nie są parsowane; user classes nie są typami w `DabType.parse`. |
| Specjalizacja funkcji | 3 | **[Fakt]** Globalna funkcja z argumentami `Object` jest klonowana do `__name_Types`, co potwierdzają goldeny `0006`, `0007`, `0034`. Brak metod, zero-argumentowych przypadków, trwałego cache i kontroli eksplozji wariantów (`concreteify_call.rb:1-23`). |
| `nil` | 3 | **[Fakt]** Runtime ma `NilClass`, opcode/node, truthiness i testy. **Kontrakt statyczny jest odwrotny od README:** każdy zwykły typ akceptuje `DabTypeNil` (`types.rb:23-25`), co utrwala `spec/compiler/can_assign_spec.rb:15`. |
| Klasy | 3 | **[Fakt]** Klasy, konstruktory, static methods i classvars mają kod i testy (`0151`, `0226`, `0241`–`0243`). Parser przyjmuje destruktor, lecz nie znaleziono wiarygodnej ścieżki jego wykonania przez runtime. |
| Dziedziczenie | 3 | **[Fakt]** Parent trafia do metadanych, VM rekurencyjnie wyszukuje metodę i sprawdza subclass (`node_class_definition.rb:56-91`, `src/cvm/class.cpp:13-33,51-60`, test `0120_subclass`). Brak wykrywania cykli i spójności z systemem typów. |
| Funkcje | 4 | **[Fakt]** Globalne funkcje, arity, default args, wynik, bloki i calls są centralne i szeroko testowane (`node_function.rb:29-80,185-215,343-353`; `0223`–`0225`). |
| Metody | 3 | **[Fakt]** Instance/static dispatch, konstruktory i classvars działają. Statyczne sprawdzenie metod jest ograniczone do receivera o znanym konkretnym typie; kontrakt argumentów metod nie jest kompletny. |
| Closures / bloki | 4 | **[Fakt]** Bloki są obniżane do syntetycznych klas/metod, a capture używa boxów (`extract_call_block.rb:1-70`, `node_closure_var.rb:3-37`); wiele fixture’ów obejmuje capture i yield. Serializer dynamicznych metod w Rings przyjmuje jednak tylko capture `Fixnum`/`String` (`define_method.cpp:98-133`). |
| Moduły / namespaces | 0 | **[Fakt]** Top-level przyjmuje wyłącznie functions i classes (`context.rb:52-71`); brak `module`, `namespace`, importów, visibility i izolacji nazw. Multi-file oraz Rings nie są systemem modułów. |
| Wyjątki językowe | 0 | **[Fakt]** Brak gramatyki `try`/`throw`/`catch`. `DabRuntimeError` jest host exception łapanym na szczycie procesu, nie obsługiwanym przez kod Dab (`cvm.h:11-29`, `main.cpp:1522-1530`; `TODO.md:8`). |
| Pamięć / GC | 1 | **[Fakt]** Istnieje eksperymentalne retain/release i autorelease, ale nie GC; cykle wyciekają, ownership nie jest formalne, a `DabValue::operator=` nie zwalnia poprzedniej referencji (`dab_value.cpp:498-518`). Disabled leak fixtures i `TODO.md:7` potwierdzają niedomknięcie. |
| ABI / FFI | 2 | **[Fakt]** POSIX `dlopen`/`dlsym`, pointer casts i kilka sygnatur działają w testach. Windows jest TODO, handle nie są zamykane, typy ABI są skończoną wygenerowaną drabiną, a pointer conversions są niebezpieczne (`syscalls.cpp:52-122`, `main.cpp:1088-1131`). |
| Generics | 1 | **[Fakt]** Parser zapisuje template params i istnieje jeden test `0246_class_template`. VM hardcoduje indeks instancji `4096`, parametry nie typują body i instancje mogą kolidować (`main.cpp:778-804`). |
| Metaprogramowanie | 3 | **[Fakt]** Reflection, attributes, `define_class` i `define_method` są realne (`CreateAttributes`, `define_method.cpp:4-234`). Generator dynamicznych metod ręcznie składa bytecode i ma bardzo ograniczony capture oraz diagnostykę. |
| Rings | 3 | **[Fakt]** Kompilator czyta starsze obrazy jako stuby, a VM snapshot jest wejściem kolejnej warstwy (`readbin.rb`, `frontend_multidab.rb:27-72`). Brak dependency graph, provenance, sandboxa, hash cache i automatycznej invalidacji. |
| Caching | 2 | **[Fakt]** Cache traversal poddrzew AST jest testowany (`node.rb:96-127`, `cache_spec.rb`). „Cache” builda to ręcznie wskazane Ring bases; TODO nadal żąda unified invalidation (`TODO.md:20`). |
| Debugger | 2 | **[Fakt]** REPL VM obsługuje step, registers, classes, functions, constants, IP i breakpointy (`debug.cpp:10-266`) i ma siedem goldenów. `print_stack` jest pusty, brak source-level locals i stack trace. |
| Source maps / odpowiednik | 2 | **[Fakt]** Parser i nodes zachowują file/line/char, coverage emituje file+line (`parser.rb:21-52,91-111`, `node.rb:246-282`). Nie istnieje utrwalona mapa bytecode-IP→source dla debuggera. |
| Formatter | 3 | **[Fakt]** Parse→`formatted_source` ma 31 goldenów. Jest stratny: usuwa komentarze, a część node formatters pomija return type, typy argumentów, parent/templates; nie jest bezpiecznym round-tripem semantycznym. |
| Coverage | 3 | **[Fakt]** Compiler emituje `COV`, VM liczy linie, a Ruby agreguje raport (`node_unit.rb:181-213`, `cvm/coverage.cpp:3-35`, `cov.rb:20-82`). Brak branch coverage, a ścieżka końcowa ma tylko jeden fixture (`TODO.md:67-68`). |
| Decompiler | 2 | **[Fakt]** Odtwarza podzbiór AST z disassembly i ma 24 aktywne goldeny (`decompile.rb:26-155,193-235`). Nieznany opcode przerywa pracę, parent classes są TODO, a typy/nazwy/closures są tracone. |
| Multi-file | 3 | **[Fakt]** CLI parsuje kilka wejść do wspólnego `DabNodeUnit` (`parts/main.rb:58-75`), co wykorzystuje stdlib. Brak import graph i izolacji; globalna przestrzeń oraz kolejność plików są częścią zachowania. |
| Standard library | 2 | **[Fakt]** 11 plików / 286 linii Dab plus natywne builtiny daje podstawowe Array, String, Fixnum, Object, Set, I/O i FFI. Brak Hash, Range, regexp, pełnego I/O/networkingu, package managera i ekosystemu. |

### 4.1 Najważniejsze rozbieżności dokumentacja–implementacja

1. `README.md:23-29` mówi, że typed values domyślnie nie przyjmują `nil`; `types.rb:23-25` i spec mówią przeciwnie.
2. `README.md:21` opisuje szeroką inferencję oraz universal implementation + specialization; kod wykonuje wyłącznie lokalną propagację i wąski cloning global calls.
3. `README.md:55` obiecuje optymalizację i IDE autocompletion dla wygenerowanych metod; snapshot daje widoczność nazw w następnym Ring, ale repo nie zawiera IDE, language servera ani dowodu stabilnej optymalizacji.
4. `README.md:57` nazywa Rings cachingiem; nie ma dependency graph, content hashes ani invalidation, a `TODO.md:20` wprost wymienia ten brak.
5. „Create everything, from low-level to high-level” (`README.md:17`) nie ma pokrycia w przenośności, bibliotekach, native codegen, modułach, wyjątkach ani security boundary.

### 4.2 Funkcje martwe, porzucone lub poza `master`

- **[Fakt]** `origin/c_export` jest niepołączonym eksperymentem C embedding/function literals i nie może być przedstawiany jako obecne API.
- **[Fakt]** `origin/orm-example`, `webserver-upgrade` i `__call` przechowują osobne próby ARC/ORM/web/closure semantics, które nie weszły do `master`.
- **[Mocna przesłanka]** Stare AppVeyor/Travis/Docker instructions są artefaktami historycznymi, nie wiarygodnymi ścieżkami wsparcia.
- **[Fakt]** Native compilation, namespaces, exceptions, nullables/final types, package manager, IDE i Windows DLL import pozostają na liście TODO.

## 5. Wyniki builda i testów

### 5.1 Oficjalna procedura a czysty checkout

Dokumentowana procedura to Ruby + Bundler + Premake 5 + GCC/Clang, następnie `bundle install` i `bundle exec rake` (`docs/building.md:6-15`). Konkretne instrukcje GNU/Linux nadal pinują Ruby 2.3 i Premake alpha11 z 2017 roku (`docs/building.md:34-47`), podczas gdy `.ruby-version` wymaga 3.1.6, lockfile Bundlera 2.5.21, a workflow pobiera Premake beta2 (`.github/workflows/ruby.yml:26-40`). Są to trzy różne kontrakty środowiska.

| Próba | Wynik | Wniosek |
|---|---|---|
| `bundle exec rake` w czystym checkoutcie | **FAIL przed startem**: lokalny rbenv nie ma wymaganego Ruby 3.1.6 | instrukcja „po prostu rake” nie jest samowystarczalna; brak bootstrapu |
| izolowany checkout, dostępne Ruby 3.3.x + `bundle install` + Premake 5 beta2 + GCC 15 | **FAIL build**: `-Werror=format-truncation` w `src/cdisasm/disasm.cpp:363` | współczesny GCC znajduje problem blokujący, bo Premake ustawia fatal warnings |
| ten sam checkout + Clang 21 | **FAIL build**: dangling pointer w `src/cvm/main.cpp:1092` | drugi toolchain niezależnie ujawnia realny błąd czasu życia |
| GCC 15 z wyłącznie środowiskowym `CXXFLAGS=-Wno-error=format-truncation` | binaria powstają, duża część testów przechodzi, potem `multidab` abortuje | kod jest nadal uruchamialnym prototypem, ale nie ma zielonego default pipeline |
| `bundle exec rspec` uruchomione osobno | 70 examples: 53 pass, 1 failure, 16 pending; seed 2297 | RSpec nie jest zielone i nie jest częścią `rake default` |
| `rake decompile_spec` osobno | 24/24 pass, 13,05 s | częściowy decompiler ma działające goldeny |
| `rake compiler_performance_spec` osobno | 2/2 pass, 2,10 s | tylko mikropomiary kompilatora; zadanie poza default |
| `timeout --kill-after=5s 35s ... rake -B build_examples_spec` | nadal kompilował `examples/0003_database.dab`; zewnętrzny timeout zakończył exit 124 po 35,20 s | harness drukuje timeout 30, ale go nie egzekwuje (`src/shared/system.rb:120-127`) |

Po obejściu pierwszego `-Werror` przeszły następujące aktywne zestawy: 240/240 Dab, 5/5 minitest, 31/31 formatter, 35/35 VM, 10/10 disassembler, 102/102 assembler, 2/2 dumpcov, 1/1 coverage i 7/7 debugger. W `multidab` dziesięć przypadków przeszło, po czym `test/multidab/0002_multilevel.test` zakończył proces asercją bounds w `std::vector`; default suite nie doszedł do końca. Przyczyna jest konkretna: `bin_save.cpp:117-136` oblicza indeksy `last_data`/`last_code`, `:138-154` usuwa wcześniejsze sekcje, a `:159` indeksuje skurczony wektor starym `last_code_index`. Wynik nie jest więc „prawie zielony” w sensie release gate: awaria dotyczy właśnie wyróżnika projektu.

Aktywna porażka RSpec to `spec/compiler/readbin_spec.rb:155`; `readbin.rb:102` rzuca `ArgumentError: @ outside of string`. To dodatkowo dotyka parsera binarnego używanego przez Rings, a nie pomocniczego testu kosmetycznego.

**Ocena clone-to-first-run:** [Mocna przesłanka] dla nowej osoby bez przygotowanego Rubiego czas jest nieprzewidywalny, ponieważ repo nie dostarcza bootstrapu Premake/Ruby ani preflightu. Do pierwszego programu prowadzi implicit build wielu generatorów i natywnych binariów; pierwszy komunikat dotyczy wersji hosta, późniejsze dotyczą ostrzeżeń C++, nie modelu Dab.

### 5.2 Co naprawdę uruchamia `rake`

`Rakefile:224-236` definiuje osobne rodziny fixture’ów. `Rakefile:267-269` w default zawiera docs generators, native VM/disassembler oraz minitest, Dab, formatter, VM, disasm, asm, dumpcov, coverage, debugger, multidab i decompiler. Nie zawiera:

- prawdziwego RSpec — `task spec: :dab` (`Rakefile:250-251`) jest mylącą nazwą;
- `compiler_performance_spec`;
- `build_examples_spec`;
- Ruby SimpleCov, chyba że użytkownik ręcznie ustawi `COVERAGE` (`Rakefile:3-7`);
- sanitizerów, fuzzingu i testów kilku platform.

### 5.3 Inwentarz testów

| Rodzina | Aktywne | Co sprawdza | Istotna wada |
|---|---:|---|---|
| `test/dab/*.dabt` | 240 | compile→assemble→VM i oczekiwane wyjście/assembler | tylko 16 compile-error i 1 runtime-error; dużo goldenów |
| `test/minitest/*.dab` | 5 | małe programy ze stdlib | znikome pokrycie biblioteki |
| `test/format/*.dabft` | 31 | exact formatted output | nie sprawdza zachowania po round-tripie |
| `test/vm/*.vmt` | 35 | bezpośrednie opcode/VM | nie obejmuje malformed binaries ani memory safety |
| `test/asm/*.asmt` | 102 | encoding assemblera | dokładny byte/tekst utrwala implementację |
| disasm/dumpcov/cov/debug | 20 | narzędzia wokół bytecode | głównie happy paths |
| `test/multidab/*.test` | 12 | wielowarstwowe Rings, dynamic methods/classes | jeden aktywny przypadek obecnie abortuje; ivar case jest disabled |
| `test/decompile/*.test` | 24 | decompile goldens | pełny VM round-trip jest disabled |
| compiler performance | 2 | koszt wybranych transformacji | mają machine-sensitive `acceptable_time` (`frontend_compiler_performance.rb:45-61`), ale brak runtime benchmark i trend/baseline gate |
| `spec/**/*_spec.rb` | 23 pliki | jednostki parsera/compiler transforms/cache/readbin | 16 `xit`; jedna aktywna porażka; poza default |

Wyłączone są między innymi sześć leak tests (`test/dab/0199`–`0204` jako `.dabtx`), dynamiczna metoda z instance variable (`test/multidab/0012_define_ivar.testx`) i decompiler VM round-trip (`test/decompile/0025_vm.testx`). To nie są przypadkowe ozdobniki: dotykają pamięci, Rings i pełnego toolchainu.

### 5.4 Wiarygodność zielonego suite

**Co zielony wynik by potwierdzał:** zgodność z około 450 znanymi małymi fixture’ami, stabilność tekstowego assemblera, podstawowe wykonanie opcode, wybrane transformacje AST oraz podstawową kompatybilność narzędzi z własnym formatem.

**Czego nie potwierdzałby:**

- poprawności dla złośliwego lub uszkodzonego `.dabcb`;
- braku UB, use-after-free, leaks, invalid iterator i integer/size overflow;
- deklarowanej semantyki typów, bo część speców utrwala zachowanie sprzeczne z README;
- działania na Windows/macOS, big-endian lub innym ABI;
- deterministyczności i poprawnej invalidacji Rings;
- skalowania kompilatora/VM i wydajności aplikacyjnej;
- bezpieczeństwa FFI; są tylko dwa pozytywne testy (`0244_ffi_simple`, `0245_ffi_arg`);
- jakości diagnostyki dla szerokiego zbioru błędnych programów;
- kompatybilności formatter/decompiler jako bezstratnych round-tripów;
- examples i realnego workloadu.

**Ocena:** nawet hipotetycznie zielony default suite dawałby **umiarkowaną pewność regresyjną dla prototypu, niską pewność poprawności języka i bardzo niską pewność bezpieczeństwa runtime**. Obecny suite dodatkowo używa zadań plikowych zależnych od timestampów (`Rakefile:190-220`), więc powtórne uruchomienie może korzystać z istniejących `.out`, jeśli nie wymusi się czystego katalogu.

### 5.5 Najbardziej niebezpieczne luki testowe

1. Malformed/truncated/oversized section tables i function metadata w loaderze.
2. ASan/UBSan coverage dla castów pointer/String/ByteBuffer, `DabValue` ARC i builtin collections.
3. FFI: błędne signatures, callbacks, null pointers, lifetime i Windows.
4. Rings: crash recovery, provenance, stale base, zmiana wcześniejszej warstwy, deterministyczny snapshot i równoległy build.
5. Cycles, overwrite assignment, destructor semantics i disabled leak fixtures.
6. Parser fuzzing, deep nesting, ogromne strings/comments i diagnostyka EOF.
7. Generyki z dwiema instancjami, inheritance i kolizją indeksu 4096.
8. Endianness, 32-bit, ARM64, macOS dylib i rzeczywisty Windows build.
9. Formatter oraz decompiler semantic round-trip.
10. Duże programy, wiele plików i ograniczenia względnych skoków `int16`.

### 5.6 CI i aktualność narzędzi

- Workflow używa Ubuntu-only i macierzy Ruby 3.0.7–3.3.5 (`.github/workflows/ruby.yml:19-40`); nie testuje macOS/Windows, sanitizerów ani RSpec.
- Publiczny workflow **Ruby** pokazywał zero runs, więc plik YAML nie jest dowodem działającego CI: [GitHub Actions — Ruby](https://github.com/thomas-pendragon/dablang/actions/workflows/ruby.yml).
- Ruby 3.1 jest EOL, a oficjalne wydania obejmują nowsze linie: [Ruby downloads](https://www.ruby-lang.org/en/downloads/).
- Repo pobiera Premake 5 beta2, podczas gdy lista upstream zawiera nowsze bety: [Premake releases](https://github.com/premake/premake-core/releases).
- `actions/checkout@v3` jest przestarzałe wobec aktualnych wydań: [actions/checkout releases](https://github.com/actions/checkout/releases).
- Legacy `.travis.yml`, `appveyor.yml` i Docker Ubuntu 16.04 opisują inne wersje Ruby/Premake/toolchainu. Windows branch `kernel_dlimport` dodatkowo odwołuje się do nieistniejącej zmiennej `args` (`src/cvm/syscalls.cpp:113-118`), więc wsparcie Windows jest obecnie nie tylko nieprzetestowane, ale źródłowo niebudowalne.

Dodatkowe pomiary toolingu:

- `bundle outdated --parseable` wskazał 20 przestarzałych direct/transitive packages; między innymi RuboCop 1.66.1→1.88.2, SimpleCov 0.22→1.0.3 i `ffi` 1.16.3→1.17.4, przy czym Gemfile świadomie blokuje `ffi < 1.17`.
- Zablokowany RuboCop przeszedł: 217 files, 0 offenses, 15,43 s. Nie ma jednak jawnego non-mutating taska; `format:ruby` uruchamia potem autocorrect `-a` (`Rakefile:303-306`).
- `rake format:stdlib_check` failuje na `stdlib/array.dab:85`, `format:sort_check` przechodzi, a `format:cpp_check` kończy się natychmiast z powodu brakującego i nieudokumentowanego `clang-format`.
- Zwykłe `rake --tasks` nie pokazuje tasków, bo nie mają `desc`; odkrywalność CLI jest niska.
- Premake tarball jest pobierany bez weryfikacji checksum. W audycie pobrany beta2 miał SHA256 `4186b8fd66b55df935280f55663c6e46fd568799d89b7ff6a3cfb20d58ff6224`, ale repo tego nie pinuje.

### 5.7 Minimalny nowoczesny workflow developerski — propozycja, nie implementacja

1. Wybrać jedną wspieraną linię Ruby i zapisać ją w `.ruby-version`, CI oraz docs; dodać preflight pokazujący brakujące narzędzie i dokładną komendę.
2. Dostarczyć `bin/bootstrap` oraz `bin/check` albo równoważny kontener/devcontainer; Premake pinować wraz z SHA256 lub zastąpić dopiero po osobnej decyzji.
3. Rozdzielić `build`, `test-unit`, `test-e2e`, `test-rings`, `test-tools`, `test-security` i `test-examples`; `all` ma uruchamiać również RSpec.
4. W CI zawsze budować z czystego checkoutu i pustego `tmp`; uploadować logi, wersje narzędzi oraz wynik każdego taska.
5. Macierz minimum: Linux GCC + Linux Clang; po naprawie źródeł macOS ARM64 i Windows MSVC. Osobny build Debug ASan+UBSan.
6. Generatory uruchamiać w trybie check, który failuje na diffie, bez milczącej modyfikacji tracked files.
7. Dodać jedno polecenie `dab run hello.dab` lub skrypt składający obecne kroki; cel pierwszego uruchomienia powinien być mierzalny i niewymagający wiedzy o Rings.
8. Pinować format DAB i testować backward/forward rejection oraz malformed corpus.

## 6. Mocne strony

### 6.1 Największe mocne strony

| Mocna strona | Dowód | Znaczenie | Możliwe wykorzystanie |
|---|---|---|---|
| Kompletny pionowy prototyp | compiler→assembler→sekcyjny bytecode→VM i narzędzia; setki fixture’ów | dużo więcej niż parser-demo; można badać zmianę semantyki end-to-end | baza laboratorium compiler/VM |
| Rings jako utrwalone metaprogramowanie | `readbin`, `frontend_multidab`, `bin_save`, dynamic define methods/classes | wygenerowane API jest materializowane przed kolejną kompilacją | demonstrator staged DSL/codegen |
| Jawny, generowany katalog opcode | `src/shared/opcodes.rb` generuje C++/docs/debug tables | ABI jest przynajmniej centralnie opisywane | formalizacja specyfikacji i validatora |
| Bogaty zestaw małych fixture’ów | 240 Dab, 102 asm, 35 VM, 31 formatter, 24 decompiler | pozwala bezpieczniej konserwować archeologię zachowania | characterization suite przed refaktorem |
| Widoczna pipeline transformacji | 17 kategorii processorów, SSA/lowering/fixed point | dobry materiał edukacyjny i pole eksperymentów | tracing passów, wizualizacja IR |
| Narzędzia wokół VM | disasm, debug, coverage, decompiler, formatter | autor rozumiał, że język to więcej niż parser | zachować jako spójne narzędzia eksperymentalne |
| Mała, czytelna semantyka bytecode | około 40 realnych opcode, rejestrowy model | relatywnie tani obszar do specyfikacji i fuzzingu | embeddable VM po utwardzeniu |
| Liberalna licencja MIT | `LICENSE`, `README.md:7` | usuwa barierę badawczego reuse | przykłady, kurs, fork eksperymentalny |

### 6.2 Najbardziej niedocenione elementy

1. **Characterization corpus assemblera/VM.** Goldeny są kruche jako produktowe testy, lecz świetnie utrwalają historyczne ABI przed jego specyfikacją.
2. **`readbin` jako most bytecode→model kompilatora.** To techniczny rdzeń widoczności wcześniejszego Ring, ważniejszy niż marketingowa nazwa.
3. **Snapshot zmienionej VM.** Jest kosztowny i ryzykowny, ale stanowi rzadki, konkretny eksperyment „wykonaj teraz, kompiluj przeciw skutkom później”.
4. **Debug/coverage/decompile w tak wczesnym prototypie.** Zakres jest płytki, lecz przekrój narzędzi może służyć do pokazania całego lifecycle bytecode.
5. **Historia 2492 małych commitów.** Mimo słabych opisów pozwala odtworzyć ewolucję designu, porzucone gałęzie i realną kolejność eksperymentów.

## 7. Słabe strony i jakość techniczna

### 7.1 Ocena przekrojowa jakości

| Wymiar | Ocena | Dowód i konsekwencja |
|---|---|---|
| Spójność architektury | niska–umiarkowana | pipeline jest czytelny koncepcyjnie, ale granice AST/IR/semantyki/backendu są zlane w `DabNode` |
| Jakość abstrakcji | niska–umiarkowana | processor registry umożliwia eksperymenty, lecz 17 implicit phases i callbacks utrudniają local reasoning |
| Czytelność/nazewnictwo | umiarkowana | małe klasy node pomagają; `extremely_early_init`, `very_early_init`, globals i terse errors nie opisują kontraktów |
| Modularność | niska | Ruby globals, singleton VM, duże `main.cpp`/`context.rb` i powielony format binarny |
| Separacja parser/semantyka/backend/runtime | niska–umiarkowana | pliki są fizycznie rozdzielone, lecz nodes znają parsing/source/SSA/format/codegen, a types mirrorują builtiny VM |
| Stan globalny/reentrancy | bardzo niska | `$VM` ma 126 tekstowych referencji w `src/cvm` i wymusza jedną VM/proces (`main.cpp:7-25`, `cvm.h:691-695`); compiler używa wielu globals |
| Obsługa błędów | niska | mieszanka 10 compiler errors, Ruby raises, C++ exceptions, `assert`, `exit(1)` i stderr |
| Diagnostyka kompilatora | niska–umiarkowana | source annotations istnieją, lecz znane missing-var errors raportują pozycję 0, a parser nie recoveruje |
| Odporność na błędne wejście | bardzo niska | loader ufa header/offset/count, native builtins nie sprawdzają bounds, VM często polega na asercjach |
| Determinizm builda | niska | sortowanie części symboli pomaga, lecz Rings wykonują kod/FFI i nie mają provenance/hash/dependency invalidation |
| Przenośność | bardzo niska | host-endian `S/s`, raw struct casts, POSIX-only FFI, zepsuty Windows branch, macOS x86_64 pin |
| Bezpieczeństwo pamięci | bardzo niska | potwierdzone leaks, dangling pointers, OOB/invalid iterators i unchecked pointer reads |
| Zarządzanie zasobami | bardzo niska | `dlopen` handles niezamykane, `strdup` bez ownership, ARC z błędnym overwrite i bez cycles |
| Wydajność VM | nieudowodniona | giant switch/interpreter i dynamiczne wartości; brak runtime benchmarks, JIT i danych profilingowych |
| Skalowalność kompilatora | niska–nieudowodniona | wielokrotne `all_nodes`, fixed-point, dup/backtracking i per-character line map; brak dużych workloadów |
| API wewnętrzne | niska–umiarkowana | proste Ruby nodes są plastyczne, ale kontrakty są implicit i zależne od kolejności faz |
| Dług techniczny | bardzo wysoki | 77 jawnych pozycji w `TODO.md`, stare deps/docs, disabled tests, abandoned branches, brak spec formatu/języka |
| Ryzyko regresji | wysokie | szerokie sprzężenie ABI i AST, RSpec poza default, goldeny utrwalają output zamiast invariants |

### 7.2 Największe słabe strony

| Problem | Konkretny dowód | Konsekwencja / koszt pozostawienia | Przybliżony koszt naprawy |
|---|---|---|---:|
| Brak prawdziwego kontraktu języka | README przeczy `types.rb`; TODO zawiera podstawową semantykę | każdy nowy feature może utrwalać inny Dab; docs i testy nie rozstrzygają sporu | L |
| Niezaufany loader jest niebezpieczny | raw casts, assert-only bounds, zaufane counts/offsets w `bin_load.cpp`/`stream.*` | crash, OOB read, resource DoS przy obcym `.dabcb`; potencjalnie cięższy wpływ | L |
| Błędy pointer lifetime / UB | `main.cpp:1088-1131`, `buffer.cpp:34`, unchecked builtins | silent corruption i niestabilne FFI nawet dla poprawnego programu | M–L |
| Eksperymentalne ARC bez GC | `dab_value.cpp:498-518`, disabled leak tests | leaks, cycles i niejasna semantyka destruktorów blokują dłuższe procesy | XL |
| Brak reprodukowalnego builda | trzy różne wersje docs/YAML; współczesne kompilatory failują | contributor odpada przed pierwszym programem; brak wiarygodnej regresji | S–M |
| Default suite nie jest pełny ani zielony | RSpec poza default, failure, Rings abort, examples hang | fałszywe poczucie bezpieczeństwa i kosztowne regresje | S |
| Global state i zlane warstwy | `$VM`, globals Ruby, wspólny node AST/SSA/codegen | brak reentrancy, trudny parallelism, wysokie ryzyko każdego refaktoru | L–XL |
| Rings bez invalidation/sandboxa | `frontend_multidab` wykonuje poprzednią warstwę i zapisuje VM; `TODO.md:20` | nondeterminism, stale API, supply-chain/build-time code execution | XL |
| Minimalna stdlib i brak modułów | 11 plików / 286 LOC; parser tylko funcs/classes | nie da się skalować aplikacji ani ekosystemu bez konfliktów i własnych bindingów | L–XL |
| Brak celu i użytkownika | ambicja od low-level do DSL; [publiczne repo](https://github.com/thomas-pendragon/dablang) pokazuje 0 aktywnych issues/PR i brak releases | roadmapa będzie sumą ciekawych feature’ów, nie walidacją wartości | strategiczny, nie tylko kodowy |

### 7.3 Potwierdzone hotspoty bezpieczeństwa i UB

1. `Stream::_read<T>` rzutuje niealigned bytes na `T*` i opiera bounds na `assert` (`src/cshared/stream.h:215-222`); release może usunąć kontrolę.
2. `load_newformat` ufa liczbie sekcji i indeksuje tablicę nagłówka zanim udowodni rozmiar; później ufa addresses/lengths/counts (`src/cvm/bin_load.cpp:3-305`).
3. `Buffer::operator=` używa `delete[]` na pamięci alokowanej przez `malloc` (`src/cshared/buffer.cpp:19-38`).
4. `DabValue::set_data` nadpisuje dane bez release starego obiektu (`src/cvm/dab_value.cpp:498-518`).
5. String→IntPtr pobiera `c_str()` z tymczasowego `std::string`; wskaźnik natychmiast wygasa (`src/cvm/main.cpp:1088-1093`).
6. DynamicString→IntPtr używa `strdup` bez protokołu zwalniania; ByteBuffer→IntPtr używa `&vec[0]` także dla pustego bufora (`main.cpp:1095-1110`).
7. IntPtr/ByteBuffer→String wykonuje nieograniczony scan po obcej pamięci (`main.cpp:1112-1131`).
8. `Array.remove_at` tworzy invalid iterator bez bounds check, a ujemny rozmiar ByteBuffer staje się ogromnym `size_t` (`default_classes.cpp:205-213,267-278`).
9. Dzielenie/modulo/shift nie chroni zerowego lub nieprawidłowego operandu (`defaults_shared.h:6-62`).
10. `kernel_dlimport` pozwala programowi ładować dowolną bibliotekę/symbol, nie zamyka handle i na błędach kończy proces (`syscalls.cpp:52-122`).
11. Jedna generowana ścieżka FFI zwraca `DabValue(CLASS_STRING, const char*)`, podczas gdy konstruktor asertywnie wymaga `CLASS_DYNAMICSTRING` (`ffi_signatures.h:247-259`, `cvm.h:339-344`).
12. Przykład ORM alokuje `2L` bajtów, choć kontrakt `PQescapeString` wymaga `2L+1`, i przekazuje błędną długość wejścia `2L`; późniejszy ByteBuffer→String skanuje poza buforem (`examples/0004_orm/level1/orm.dab:63-68`, [libpq contract](https://www.postgresql.org/docs/16/libpq-exec.html)).
13. `last_ring_offset` nie ma inicjalizatora, a ścieżka `--bare` pomija loader i później odczytuje tę wartość przy tworzeniu symboli (`cvm.h:499`, `main.cpp:168-176,1222-1236`).
14. Licznik symboli używa 16-bitowego `dab_symbol_t`; po przekroczeniu 65 535 pętla tworzenia indeksu może się zawinąć bez limitu (`main.cpp:1222-1236`).
15. Disassembler dekoduje count `reglist` jako signed `int8`, gdy VM używa `uint8`, i porównuje `uint8` do niemożliwego 256 dla long string (`cshared/disasm.h:119-126,178-186`, `stream.cpp:101-123`).
16. SIGSEGV handler wywołuje nie-async-signal-safe `backtrace`, `fprintf` i `exit`, co może maskować pierwotny crash (`cvm/handlers.cpp:11-25`).

**Granica twierdzenia:** [Fakt] powyższe wystarczają do crashy, wycieków, dangling/OOB i resource DoS. **[Hipoteza]** część może być składnikiem wykonania kodu przez złośliwy bytecode, lecz audyt nie zbudował exploita i nie klasyfikuje tego jako potwierdzone RCE.

### 7.4 Najbardziej przecenione elementy

1. **„Strong optional static typing”.** Obecny model jest adnotacją kilku builtinów z `Object` fallback i akceptacją `nil`, nie spójnym gradual type system.
2. **„Compiler will deduct types”.** Concrete literal propagation i jedna reguła cloning nie stanowią szerokiej inferencji.
3. **Rings jako cache.** Ręczne użycie snapshotu nie daje poprawności cache bez klucza, grafu zależności i invalidation.
4. **„Low-level to high-level everything”.** Brak native backendu, modułów, wyjątków, bezpiecznego FFI i stdlib przeczy temu zakresowi.
5. **Generics.** Składnia i pojedynczy display test nie tworzą parametric polymorphism.

### 7.5 Wydajność i skalowalność — co wiadomo

- **[Fakt]** Każde wywołanie Dab przez `push_new_frame` kopiuje argumenty i cały żywy wektor rejestrów, a `pop_frame` kopiuje go z powrotem (`src/cvm/main.cpp:90-136`). Koszt call rośnie więc co najmniej z liczbą live registers, niezależnie od pracy funkcji.
- **[Fakt]** Lookup symbolu jest liniowy, a tworzenie indeksu iteruje od zera (`src/cvm/cvm.h:540-550`, `main.cpp:1222-1236`).
- **[Fakt]** Compiler wielokrotnie materializuje `all_nodes` dla całego drzewa i ponawia procesory do punktu stałego (`module_processors.rb:182-247`, `parts/main.rb:230-272`).
- **[Fakt]** Parser przechowuje pozycje per character i używa backtrackingu przez subcontexts; względne skoki bytecode mają tylko signed 16-bit (`shared/parser.rb:63-112`, `tobinary.rb:243-256`).
- **[Niezweryfikowane]** Nie ma reprezentatywnych danych pozwalających nazwać VM szybką lub wolną. Powyższe wskazuje potencjalne asymptotyczne hotspoty, ale bez profilu nie uzasadnia rewrite ani JIT.

## 8. Unikalność i analiza idei

### 8.1 Czy wizja języka jest spójna

**[Mocna przesłanka]** Ogólny cel „produktywność dynamicznego języka, opcjonalne typy, specjalizacja tam, gdzie potrzebna, łatwe zejście do C ABI” jest sensownym kierunkiem projektowym. Nie jest jednak pojedynczym mechanizmem: wymaga jednocześnie precyzyjnej semantyki obiektów i mutacji, gradual typing, optimizer/deoptimization strategy, stabilnego ABI, ownership/GC, dobrego FFI oraz narzędzi. Obecny Dab implementuje po trochu każdy z tych obszarów, ale nie ustanawia nadrzędnych invariantów, które rozstrzygają konflikty.

Najważniejsze napięcia:

- Otwarty, dynamiczny model klas i `define_method` osłabia założenia potrzebne do agresywnej specjalizacji oraz exact type `T!`.
- „Optimize only if necessary” potrzebuje profili, stabilnej reprezentacji i fallback/deoptimization; obecny cloning odbywa się statycznie tylko dla prostego callsite.
- Kontrola w stylu C wymaga jawnego ownership, layoutu, bounds i ABI; raw `IntPtr` bez tych kontraktów daje ryzyko C, ale nie jego przewidywalność.
- Produktywność Ruby zależy od bibliotek, modułów, błędów, REPL i narzędzi; sama podobna składnia nie dostarcza produktywności.
- Statically visible metaprogramming wymaga hermetycznego etapu i serializowalnego wyniku; snapshot całej zmienionej VM przenosi również przypadkowy stan.

### 8.2 Wartość modelu `Type`, `Type?`, `Type!`

**Jako design niezależny od kodu** model może być wartościowy:

- `T` = non-null value będące `T` lub podtypem;
- `T?` = `T ∪ Nil`, z obowiązkowym flow narrowing;
- `T!` = dokładna/finalna reprezentacja `T`, umożliwiająca devirtualization i layout assumptions.

To jest czytelniejsze niż obecna akceptacja `Nil` przez każdy typ. Musi jednak rozstrzygnąć: variance, exactness dla value types, mutation klasy po wcześniejszym Ring, cast failure, interakcję z `Object`, generic bounds i czy `!` jest obietnicą programisty czy dowiedzionym faktem. **[Mocna przesłanka]** Najbezpieczniej uczynić `T?` zwykłą sumą/union, a `T!` wewnętrznym wynikiem analizy lub jawną sealed/final declaration, nie trzecią luźną kategorią assignment.

### 8.3 Czym naprawdę są Rings

Operacyjnie Ring jest następującą sekwencją:

1. skompiluj warstwę przeciw symbolom poprzednich obrazów;
2. uruchom ją w VM z reflection i mutacją klas/metod;
3. zapisz cały istotny stan VM do nowego obrazu;
4. odczytaj funkcje, klasy i symbole z obrazu jako compile-time stubs;
5. skompiluj kolejną warstwę przeciw temu rozszerzonemu światu.

**[Fakt]** Dzięki temu metoda utworzona dynamicznie w Ring N jest statycznie widoczna nazwą i placementem static/instance w Ring N+1. Reader odczytuje metadata argumentów i wyniku (`src/compiler/parts/readbin.rb:114-140`), lecz `parse_ring` je odrzuca przy tworzeniu stuba (`:41-50`), a `DabNodeFunctionStub` ignoruje arglist i zwraca `Object` (`node_function_stub.rb:6-9,28-30`). Następny Ring nie dostaje więc pełnego typed API obiecanego dla IDE/optimizera. **[Fakt]** Symbol nie jest widoczny w tym samym etapie, nie ma source provenance i może być reprezentowany przez ręcznie zsyntetyzowany bytecode. **[Mocna przesłanka]** To jest rzeczywista forma multi-stage programming z serialisation-based cross-stage persistence, ale obecna jednostka serializacji — snapshot VM — jest za szeroka, a importowany kontrakt za ubogi.

Nierozwiązane pytania badawcze:

1. Jaki jest minimalny, wersjonowany i deterministyczny produkt Ring: typed declarations, AST, bytecode czy pełny heap?
2. Jak wykrywać wszystkie inputs etapu: źródła, env, pliki, czas, sieć, FFI i wcześniejsze obrazy?
3. Które wartości można legalnie przenosić między etapami i jak zachować ownership/identity?
4. Jak przypisać wygenerowany symbol do źródła generatora i pokazać go debuggerowi/IDE?
5. Jak rozstrzygać redefinition, conflicts, visibility, module ownership i versioning między Rings?
6. Czy wykonanie generatora jest czyste, capability-limited czy traktowane jak dowolny build script?
7. Jak udowodnić, że stale Ring nie zmienia semantyki programu?
8. Jak ograniczyć specjalizację i rozmiar snapshotów?

### 8.4 Konsekwencje dla IDE, cache, incremental build i reproducibility

- **IDE:** potrzebuje indeksowalnego manifestu wygenerowanych deklaracji wraz z typem, docs i source origin; disassembly stubs to za mało.
- **Cache:** klucz musi obejmować transitive Ring manifests, compiler/VM/ABI version, source content oraz zadeklarowane external inputs. Mtime i ręczny `--ring-base` nie wystarczają.
- **Incremental build:** zmiana symbolu wcześniejszej warstwy musi unieważnić dokładnie konsumentów jego publicznego fingerprintu; snapshot całej VM sugeruje invalidację całości.
- **Reproducibility:** czas, random, FFI, filesystem/network i host ABI muszą być zablokowane albo jawnie zadeklarowane. Dwa clean builds powinny dawać identyczny hash.
- **Security:** Ring generator jest kodem wykonywanym podczas builda z uprawnieniami procesu. To analogiczne zagrożenie do build scripts/procedural macros, lecz snapshot zwiększa powierzchnię trwałego stanu.

### 8.5 Co jest faktycznie unikalne

| Pytanie | Odpowiedź |
|---|---|
| Co jest unikalne w tym repo? | Połączenie własnej małej VM, runtime reflection, zapisu zmienionego obrazu i ponownego importu go do modelu kompilatora jako kolejnej warstwy. |
| Co było bardziej wyjątkowe w 2017? | Próba połączenia Ruby-like syntax, gradual typing, per-call specialization i staged runtime-image metaprogramming w jednym hobbystycznym systemie. |
| Co dziś nie jest unikalne? | Opcjonalne typy, compile-time execution, AST macros, specialization, AOT/native interop, language VMs, image-based environments i incremental caches mają dojrzałe odpowiedniki. |
| Co wygląda unikalnie przez terminologię? | „Ring” częściowo nazywa phase/stage + precompiled environment/snapshot; „concreteify” to bardzo ograniczona monomorfizacja/specjalizacja. |
| Czy Rings mogą być wyróżnikiem? | Tak, ale tylko po demonstracji hermetycznej cross-stage persistence; sama serializacja VM nie jest produktem ani gwarancją poprawności. |

### 8.6 Najbardziej wiarygodne pozycjonowanie

| Pozycjonowanie | Wiarygodność | Uzasadnienie |
|---|---|---|
| Platforma badawcza staged metaprogramming | **najwyższa** | wykorzystuje faktycznie nietypowy rdzeń Rings i nie wymaga udawania kompletnego ekosystemu |
| Edukacyjny compiler/VM project | wysoka | pełny pipeline, małe opcode, bogate goldeny i widoczne kompromisy |
| VM/runtime laboratory | umiarkowanie wysoka | dobry przekrój narzędzi, ale najpierw konieczne bezpieczeństwo |
| DSL toolkit | umiarkowana | staged generation może tworzyć DSL API; brak modułów i tooling ogranicza skalę |
| Embeddable scripting language | niska obecnie | brak stabilnego C API na `master`, singleton VM i niebezpieczny loader/FFI |
| Niszowy język systemowy | bardzo niska | brak native backendu, layout/ownership, cross compilation i bezpiecznego low-level modelu |
| Język ogólnego przeznaczenia | bardzo niska | brak podstaw semantycznych, stdlib, package ecosystem i target user |

## 9. Problemy naprawialne

Poniższa kolejność opisuje zależności, a nie atrakcyjność pracy.

### 9.1 Szybkie do naprawienia

| Problem | Objaw | Przyczyna źródłowa | Zależności | Ryzyko | Efekt | Rozmiar |
|---|---|---|---|---|---|---:|
| Fałszywy onboarding | trzy wersje Rubiego/Premake; brak preflight | docs i CI ewoluowały osobno | decyzja o wspieranej wersji | niskie | reprodukowalny pierwszy build | S |
| Niepełny default suite | RSpec/perf/examples poza `rake`; timeout nie działa | historyczne task aliases i file tasks | ustalić kanoniczny gate | niskie–średnie | wiarygodny sygnał CI | S |
| Dokumentacja przedstawia zamiary jako funkcje | `Type?`, `Type!`, cache Rings | brak status matrix i wersji language spec | zatwierdzić stan 0.1 | niskie | uczciwa komunikacja | S |
| Jawne pojedyncze UB | allocator mismatch, temporary `c_str`, invalid index | brak sanitizerów/review native | characterization tests | średnie | usuwa część crashy | M |
| Windows branch nie kompiluje | `(void)args` bez `args` | martwa platformowa gałąź | Windows compile-only CI | niskie | prawdziwa informacja o platformie | XS |
| Stare action/dependency pins | checkout v3, Ruby EOL, Premake beta2 | brak maintenance cadence | zielony build po fixach | niskie | mniejszy supply-chain/deprecation risk | S |

### 9.2 Średnioterminowe

| Problem | Objaw | Przyczyna źródłowa | Zależności | Ryzyko | Efekt | Rozmiar |
|---|---|---|---|---|---|---:|
| Brak walidatora `.dabcb` | malformed input crashuje/ufa headerom | raw struct parser zaprojektowany dla trusted output | spec formatu + corpus | wysokie | bezpieczne odrzucanie inputu | L |
| Niespójna diagnostyka | `assert`, `exit`, host exceptions, line 0 | brak wspólnego error/result model | kontrakt CLI/runtime | średnie | testowalne błędy i lepszy DX | M |
| Brak sanitizer/fuzz gates | liczne oczywiste UB pozostają | historyczny build release-only | build Debug i deterministic corpus | średnie | wykrywanie całej klasy regresji | M |
| Host-dependent binary encoding | `S/s`, type-punning, raw structs | brak normatywnej serializacji | format spec/version bump | wysokie | portability i stabilne artefakty | L |
| Stratny formatter/decompiler | gubienie typów/comments/parents | nodes są jednocześnie IR i surface syntax | source AST albo jawny scope narzędzia | średnie | brak cichej zmiany programu | M–L |
| Minimalne negative/platform tests | happy paths dominują | fixture growth bez threat modelu | error taxonomy | niskie | większa wartość zielonego CI | M |

### 9.3 Wymagające dużego refaktoru

| Problem | Objaw | Przyczyna źródłowa | Zależności | Ryzyko | Efekt | Rozmiar |
|---|---|---|---|---|---|---:|
| Jeden model AST/SSA/codegen/format | cache invalidation i implicit pass order | szybki rozwój eksperymentalny | characterization + language contract | bardzo wysokie | jawne invariants faz | L–XL |
| Global compiler/VM state | brak reentrancy/parallelism/embedding | globals i singleton `$VM` | stabilne APIs | wysokie | test isolation i embedding | L |
| Pamięć runtime | leaks, cycles, dangling ownership | częściowe ARC na dynamicznych wartościach | value/object contract | bardzo wysokie | długowieczna stabilna VM | XL |
| Ring artifact/build model | stale state, brak provenance/cache | snapshot całej VM jest API etapu | manifest/spec/sandbox | bardzo wysokie | deterministyczne staged builds | XL |
| Modules/namespaces | jedna globalna przestrzeń | gramatyka i symbol tables nie modelują units | minimalny Dab 0.1 | wysokie | skalowanie kodu i bibliotek | L |
| Bezpieczne FFI/ABI | arbitralne pointers i ad hoc signatures | raw cast ladder bez IDL/ownership | typy, memory model, platform matrix | bardzo wysokie | przewidywalny interop | XL |

## 10. Problemy fundamentalne

### 10.1 Fundamentalne problemy architektoniczne

1. **Snapshot VM jako publiczny produkt kompilacji.** Objaw: compiler, loader, runtime mutator i serializer dzielą layout. Przyczyna: najszybsza droga do zachowania wygenerowanych metod. Zależność: trzeba zdefiniować mniejszy manifest etapu. Ryzyko zmiany: bardzo wysokie. Efekt: stabilność i reprodukowalność. Rozmiar: **XL**.
2. **Brak bezpiecznej granicy bytecode.** Objaw: trusted pointers/counts i `assert`. Przyczyna: format był wewnętrznym artefaktem, ale CLI przyjmuje plik. Zależność: versioned spec i validator. Ryzyko: wysokie. Efekt: możliwość traktowania VM jako embeddable. Rozmiar: **L–XL**.
3. **Mutowalny node jako wszystkie IR.** Objaw: processors zależne od kolejności, cache i parent pointers. Przyczyna: eksperymentalna wygoda Ruby. Zależność: tests + pass contracts. Ryzyko: bardzo wysokie. Efekt: możliwość lokalnego reasoning i narzędzi. Rozmiar: **XL**.
4. **Dynamiczny object model bez rozstrzygniętego memory modelu.** Objaw: retain/release plus raw pointers/FFI. Przyczyna: próba jednoczesnej wygody i niskiego poziomu. Zależność: decyzja GC vs ARC/ownership. Ryzyko: bardzo wysokie. Efekt: usuwa całą klasę błędów. Rozmiar: **XL**.

### 10.2 Fundamentalne problemy designu języka

1. **Exact/final types kontra runtime mutation.** Jeśli późniejszy Ring może zmienić klasę/metody, założenie `T!` wymaga sealing point oraz jawnych invalidations.
2. **Gradual typing bez formalnej consistent-subtyping semantics.** Trzeba rozstrzygnąć granice `Object`, `Nil`, casts i dynamic calls; same checks assignment nie wystarczą.
3. **Metaprogramowanie z pełnymi skutkami ubocznymi kontra reprodukowalność.** Nie można jednocześnie pozwolić na arbitralny `dlopen`, pliki/sieć i obiecać poprawnego cache bez capability/input modelu.
4. **„Od C do Ruby” jako grupa docelowa.** Każdy biegun wymaga innego memory modelu, tooling, błędów i bibliotek. Bez dominującego use case ta tożsamość generuje roadmapę bez końca.
5. **Specialization jako semantyka czy optymalizacja.** Jeśli wyspecjalizowana funkcja zachowuje się inaczej od generic fallback, język jest niestabilny; jeśli identycznie, potrzebny jest dowód/guard i fallback.

### 10.3 Problemy nienaprawialne bez zmiany tożsamości

- Produkcyjna obietnica „jeden język do wszystkiego” musiałaby zostać zastąpiona konkretną niszą; samo uzupełnianie TODO jej nie waliduje.
- Bezpieczne wykonywanie niezaufanych programów wymaga odebrania lub capability-gating surowego FFI, co zmienia obecną swobodę VM.
- Deterministyczne Rings wymagają ograniczenia obserwowalnych skutków build-time code albo jawnego uznania ich za niecacheowalne; pełna dowolność i poprawny cache są sprzeczne.
- Zachowanie dokładnie obecnego binarnego ABI koliduje z przenośnym, walidowalnym formatem; potrzebna będzie wersja/migracja, nie wieczna kompatybilność.

### 10.4 Sformalizowany rekord problemów fundamentalnych

| Kategoria | Problem / objaw | Przyczyna źródłowa | Zależności naprawy | Ryzyko naprawy | Przewidywany efekt | Rozmiar |
|---|---|---|---|---|---|---:|
| architektura | snapshot VM jest jednocześnie runtime state i API kolejnego etapu | najkrótsza implementacja cross-stage persistence | manifest, codec, provenance, deterministic evaluator | bardzo wysokie | mały wersjonowany artifact i poprawny cache | XL |
| architektura | jeden mutowalny node obsługuje source/SSA/format/codegen | eksperymentalna szybkość rozwoju | frozen semantics, pass differential tests | bardzo wysokie | jawne granice i invariants | XL |
| architektura | globalna compiler session i singleton VM | brak pierwotnego embedding/concurrency target | context APIs i test dwóch instancji | wysokie | reentrancy, parallelism, test isolation | L–XL |
| język | dynamiczna mutacja klas konfliktuje z exact/final assumptions | staging, typing i optimizer powstawały osobno | sealing point, invalidation, gradual type rules | bardzo wysokie | sound basis dla `T!` lub świadome usunięcie | XL |
| język | compile-time arbitrary effects konfliktują z cache | Ring wykonuje zwykły program z FFI | capabilities, declared inputs, hermetyczność | bardzo wysokie | reprodukowalne metaprogramowanie | XL |
| język/runtime | brak decyzji GC kontra kompletne ARC/ownership | próba dynamicznej wygody z raw C interop | object/value/lifetime spec | bardzo wysokie | stabilne długowieczne programy | XL |
| tożsamość | „od low-level C do high-level Ruby” nie wybiera odbiorcy | aspiracyjny, niezwalidowany scope | charter, flagowe demo, user evidence | średnie technicznie, trudne strategicznie | możliwa skończona roadmapa | S strategiczne |
| tożsamość | untrusted embedding konfliktuje z raw FFI | VM nie ma capability/trust boundary | verifier, memory model, unsafe mode | bardzo wysokie | bezpieczna nisza albo uczciwy trusted-only scope | XL |
| tożsamość | wieczna kompatybilność DAB v3 konfliktuje z portability | host layout/type-punning w artifacts | version bump i migration policy | wysokie | canonical cross-platform format | L |

### 10.5 Dlaczego nie rekomenduję jeszcze rewrite

Pełny rewrite przed testem wartości mógłby usunąć jedyny empiryczny atut — działający przepływ Rings — i spędzić większość wysiłku na parserze, GC, module system i tooling bez użytkownika. Stopniowa modernizacja jest racjonalna do końca Fazy 2: zamrozić semantykę, uruchomić sanitizery, wyizolować manifest Ring i zbudować flagowe demo. **Rewrite części** staje się uzasadniony dopiero, jeśli te eksperymenty potwierdzą wartość, a istniejący snapshot/AST uniemożliwi wymagane invariants.

## 11. Analiza konkurencyjna i prawdziwe analogie

### 11.1 Typy, kontrola i produktywność

| System | Rzeczywista analogia | Zasadnicza różnica / lekcja dla Dab |
|---|---|---|
| Ruby | syntax, blocks, open classes, reflection i productivity-first | produktywność Ruby pochodzi też z dojrzałego runtime/stdlib/gems/tooling; Dab dziedziczy dynamikę bez ekosystemu |
| Crystal | Ruby-like surface, global inference, native code, macros i C bindings | Crystal ma semantic typing, AOT backend i AST macros; Dab używa VM, adnotacji builtinów i snapshotów. Oficjalnie macros przyjmują AST i produkują kod: [Crystal macros](https://crystal-lang.org/reference/1.20/syntax_and_semantics/macros/index.html) |
| C / C++ | raw pointers, dynamic libraries, C ABI oraz kontrola layoutu jako aspiracja | Dab nie daje językowego ownership/layout/UB modelu, więc FFI odziedzicza ryzyko bez statycznej kontroli |
| Rust | typy sum, `Option`, ownership i compile-time procedural macros | Rust oddziela macro crate/stage i nadal ostrzega, że compile-time code ma uprawnienia build procesu; to dobry threat model dla Rings: [Rust procedural macros](https://doc.rust-lang.org/stable/reference/procedural-macros.html) |
| Zig | explicit low-level control, C interop i `comptime` jako gwarancja wartości znanej podczas analizy | Zig nie serializuje dowolnie zmienionej VM; `comptime` ma jawne ograniczenia i służy też generics: [Zig language reference](https://ziglang.org/documentation/master/#comptime) |
| Swift | optional types, constrained generics i native ABI/tooling | pokazuje, ile formalnych constraints i library integration wymaga prawdziwy generic/type system: [Swift generics](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/generics/) |
| Kotlin/Native | native target i generowane C bindings | typed `cinterop` mapuje headers i jawne pointer/lifetime helpers; ad hoc signature ladder Dab jest dużo słabsza: [Kotlin/Native C interop](https://kotlinlang.org/docs/native-c-interop.html) |

`Type`/`Type?` najbardziej przypomina non-null/optional model Swift/Kotlin/Rust, a `Type!` — exact/sealed knowledge używane do devirtualization. To nie jest wyjątkowa kategoria typu, dopóki Dab nie określi subtyping, narrowing i sealing.

### 11.2 Compile-time execution i generowanie kodu

| System | Analogia do Rings | Kluczowa różnica |
|---|---|---|
| Nim | większość języka może wykonywać się compile-time, macros transformują semantically enriched AST | etap jest zintegrowany z analizą, a produkt to AST/code; [Nim Manual](https://nim-lang.org/docs/manual.html) opisuje interleaving semantic analysis i compile-time execution |
| D | templates, mixins i CTFE | CTFE oblicza wartości/kod w formalnym compile-time modelu, nie materializuje całego heap obrazu |
| Crystal | macro AST i `run` podczas kompilacji | dokumentacja ostrzega o external inputs i cache programu macro; Ring potrzebuje analogicznego, lecz szerszego kontraktu |
| Elixir | explicit, lexical, hygienic compile-time macros i środowisko modułu | Elixir ogranicza widoczność przez module/import/require i wymaga jawnego wywołania: [Elixir macros](https://hexdocs.pm/elixir/main/macros.html); Dab dynamicznie mutuje globalny świat |
| Template Haskell | quotes/splices, stages i serialisation-based cross-stage persistence (`Lift`) | GHC typecheckuje levels i stage restrictions; Dab nie ma level checker ani typu „serializable across Ring”: [GHC Template Haskell levels](https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/template_haskell.html) |
| Racket | dowolne phase levels i bindingi istniejące w konkretnych phases | Racket oddziela środowiska i komunikuje się przez expansion protocol; Dab scala snapshots: [Racket phase levels](https://docs.racket-lang.org/guide/phases.html) |
| Common Lisp | macros, `compile-file`, loadable artifacts i image-based development | Lisp image jest bliską analogią stanu, ale macro expansion/compile-time environment ma dojrzały module/package/tooling; Ring jest bardziej coarse-grained |

**Wniosek:** Rings nie wynajdują staged programming. Ich interesujący wariant polega na tym, że zwykły kod Dab mutuje VM, a wynik jest kolejnym statycznym światem. To może być przewagą dla framework/DSL generation, ale tylko gdy granice świata są bardziej jawne niż w obecnym obrazie.

### 11.3 Specialization, partial evaluation i dynamiczne runtime

| System | Analogia | Różnica / lekcja |
|---|---|---|
| Julia | generated functions specjalizują wynik względem typów argumentów i mogą być cache’owane | Julia wymaga purity, ogranicza obserwację mutable global state i opisuje world-age; dokładnie tych ograniczeń brakuje Rings: [Julia generated functions](https://docs.julialang.org/en/v1/manual/metaprogramming/#Generated-functions) |
| LuaJIT | dynamic values + trace specialization, SSA i guards | specjalizuje zachowanie runtime z fallbackiem, a nie klonuje kilka source calls; ma jawny compiled-code cache/limits: [LuaJIT](https://luajit.org/luajit.html) |
| GraalVM/Truffle | interpretery self-modifying AST, automated monomorphization i partial evaluation | inwestycja jest w wyspecjalizowany runtime/JIT oraz tooling, nie snapshot build stage: [Truffle framework](https://www.graalvm.org/jdk22/graalvm-as-a-platform/language-implementation-framework/) |
| klasyczna partial evaluation | specjalizacja programu względem statycznych wejść | wymaga rozdzielenia static/dynamic inputs i zachowania semantyki; `ConcreteifyCall` jest pojedynczą heurystyką, nie generalnym partial evaluator |

### 11.4 Czego nie należy kopiować bez powodu

- LLVM JIT/native backend nie rozwiąże semantyki, memory safety ani popytu; to późny wybór backendu, nie plan ratunkowy.
- Borrow checker Rust byłby zmianą tożsamości, a nie „naprawą ARC”.
- Pełny hygienic macro system obok Rings rozmyłby eksperyment; najpierw trzeba wykazać, czego snapshot stage dokonuje lepiej.
- Graal/LLVM jako ciężka zależność podniosłyby próg contributora bez dowodu, że VM performance jest blockerem.
- Kopiowanie stdlib Ruby nie tworzy kompatybilności; minimalny demonstrator powinien mieć mały jawny zakres.

## 12. Scenariusze rozwoju

Prawdopodobieństwa są celowo jakościowe. Repo nie daje podstaw do wiarygodnych, precyzyjnych procentów adopcji.

### A. Konserwacja i archiwizacja

| Pole | Ocena |
|---|---|
| Cel | odtwarzalny build, prawdziwy opis funkcji, zachowane artefakty i przewodnik po architekturze |
| Inwestycja | **M**: środowisko, characterization suite, docs, naprawa blockerów buildu i oznaczenie unsafe |
| Główne ryzyka | „archiwizacja” stanie się pretekstem do niedokończonego cleanupu; toolchain ponownie zgnije |
| Potencjalna wartość | wysoka edukacyjna, umiarkowana historyczna, niska produktowa |
| Techniczne powodzenie | **wysokie** |
| Realni użytkownicy | **bardzo niskie–niskie**, głównie studenci i autorzy compilerów |
| Warunki konieczne | jeden clean build, wszystkie wspierane testy sklasyfikowane, release artifact, status każdej obietnicy |
| Sygnał porzucenia | nawet minimalnego builda nie da się utrzymać albo nikt nie zaakceptuje roli projektu archiwalnego |

### B. Modernizacja istniejącego Dab

| Pole | Ocena |
|---|---|
| Cel | zachować Ruby compiler, format/VM i szeroki language vision, stopniowo dojść do używalnego general-purpose language |
| Inwestycja | **XL**, wielotorowa: spec, typy, memory, modules, runtime, FFI, tooling, stdlib, platformy |
| Główne ryzyka | wieczny eksperyment, kompatybilność ze sprzecznym zachowaniem, brak odbiorcy, contributor bottleneck |
| Potencjalna wartość | wysoka tylko w odległym sukcesie; po drodze słaba |
| Techniczne powodzenie | **niskie–umiarkowane** |
| Realni użytkownicy | **bardzo niskie** bez odrębnej, przekonującej przewagi |
| Warunki konieczne | wieloletnia odpowiedzialność maintainerów, formalny scope 0.1, zewnętrzni contributorzy, demonstrator popytu |
| Sygnał porzucenia | roadmapa znów zaczyna od nowych features; po Fazie 2 nadal brak reprodukowalnego value demo |

### C. Zachowanie idei, wymiana implementacji

| Pole | Ocena |
|---|---|
| Cel | zachować składnię/test corpus/Rings concept, wymienić codec, VM lub część compiler IR |
| Inwestycja | **L–XL** zależnie od granicy; differential harness jest obowiązkowy |
| Główne ryzyka | rewrite trap, utrata subtelnej semantyki, dwa runtime przez długi czas, brak dowodu wartości |
| Potencjalna wartość | umiarkowanie wysoka, jeśli bezpieczeństwo/concurrency są niemożliwe w obecnym native core |
| Techniczne powodzenie | **umiarkowane** dla wymiany codec/VM, niskie dla pełnego rewrite |
| Realni użytkownicy | **niskie**, dopóki wynik nie daje konkretnego produktu |
| Warunki konieczne | zamrożony Dab 0.1, golden/differential corpus, jawne invariants, mała wymieniana granica |
| Sygnał porzucenia | nowa implementacja nie dogania corpus lub pochłania pracę nad flagowym demo |

### D. Radykalne zawężenie celu

| Pole | Ocena |
|---|---|
| Cel | eksperymentalna platforma staged metaprogramming/Rings z małą VM i jednym hermetycznym DSL demo |
| Inwestycja | **M–L** do wiarygodnego demonstratora; **XL** tylko po pozytywnej walidacji produktu |
| Główne ryzyka | Rings okażą się bardziej złożoną wersją zwykłego codegen; hermetyczność wymusi duży redesign |
| Potencjalna wartość | najwyższy stosunek unikalności do kosztu; publikowalny eksperyment i narzędzie DSL |
| Techniczne powodzenie | **umiarkowanie wysokie** dla demonstratora |
| Realni użytkownicy | **niskie–umiarkowane** w niszy DSL/compiler research, jeśli UX jest wyraźnie lepszy |
| Warunki konieczne | manifest etapu, typed stubs, provenance, identyczne rebuildy, poprawna invalidation, bezpieczny evaluator |
| Sygnał porzucenia | prosty generator plików daje ten sam efekt taniej albo dwa clean builds nie są identyczne |

### 12.1 Porównanie scenariuszy

| Scenariusz | Wartość przy małej inwestycji | Zachowanie istniejącego kodu | Unikalność | Ryzyko | Rekomendacja |
|---|---:|---:|---:|---:|---|
| A | wysoka | bardzo wysokie | niska–umiarkowana | niskie | wariant zapasowy |
| B | niska | wysokie na początku | umiarkowana | bardzo wysokie | nie teraz |
| C | niska–umiarkowana | średnie | umiarkowana | bardzo wysokie | tylko po dowodzie Fazy 2 |
| D | najwyższa | wysokie dla rdzenia | najwyższa | umiarkowane–wysokie | **kierunek główny** |

## 13. Rekomendowany kierunek

### 13.1 Kierunek główny: D — hermetyczne Rings jako platforma badawcza/DSL

Proponowane pozycjonowanie:

> **Dab jest eksperymentalnym laboratorium staged metaprogramming i bytecode VM. Rings uruchamiają generator w jednej warstwie i udostępniają wersjonowany, typowany wynik kompilatorowi następnej warstwy.**

Dlaczego:

- **Wartość techniczna:** wykorzystuje działające `readbin`/snapshot/dynamic definitions, zamiast zaczynać od zera.
- **Unikalność:** to jedyny fragment, dla którego kombinacja mechanizmów jest wyraźnie odróżnialna od tutorialowego języka.
- **Koszt:** demonstrator wymaga M–L, nie całego ekosystemu general-purpose.
- **Ryzyko:** można je ograniczyć bramkami hash/provenance/invalidation; wynik negatywny też jest wartościową wiedzą.
- **Szybki dowód:** schema→generated typed API→compile-time error da jednoznaczny rezultat.
- **Contributor appeal:** mały problem badawczy jest łatwiejszy do wyjaśnienia niż 77 TODO języka „do wszystkiego”.
- **Zgodność z kodem:** zachowuje Ruby frontend, małą VM, reflection, bin tools i fixtures.

### 13.2 Flagowe demo

**Hermetyczny generator modelu ze schematu:**

```text
Ring 0: minimalny runtime + bezpieczny evaluator
Ring 1: generator czyta zadeklarowany schema.json
        -> tworzy model User, fields i typed query API
        -> emituje manifest deklaracji + source provenance
Ring 2: aplikacja korzysta z User.name i find_by_name(String)
        -> próba User.nonexistent musi failować podczas kompilacji
```

Kryteria:

1. Dwa clean builds dają byte-identical artifacts i ten sam manifest SHA.
2. Zmiana tylko aplikacji daje cache hit Ring 1.
3. Zmiana schema unieważnia Ring 1 i dokładnych konsumentów.
4. Stub zachowuje arity, argument types, return type, static/instance i source origin.
5. Błąd wygenerowanego API wskazuje schema oraz generator.
6. Generator nie ma niezadeklarowanej sieci, czasu ani filesystem access.
7. Porównanie z prostym `generate.rb > model.dab` pokazuje mierzalną przewagę: mniej kroków, lepsza widoczność lub poprawniejszy incremental build.

Nie należy używać obecnego ORM/PostgreSQL jako flagowego demo: zależność od żywej bazy niszczy hermetyczność, a `PQescapeString` example zawiera potwierdzony błąd bufora.

### 13.3 Wariant zapasowy: A — zachowanie jako projekt edukacyjny

Jeśli manifest/provenance/determinism nie przejdą bramki Fazy 2, należy zakończyć expansion i opublikować odtwarzalny snapshot: wspierany container, architekturę, language truth table, corpus, listę znanych unsafe paths i walkthrough jednego programu. To zachowuje istniejącą wartość bez udawania produktu.

### 13.4 Dlaczego nie B ani pełny C

- B maksymalizuje koszt przed walidacją jedynego wyróżnika.
- Pełny C ryzykuje usunięcie informacji zawartej w 2492 commitach i fixture’ach.
- C ma sens punktowo: nowy bounded codec/reader, a później ewentualnie nowy VM core, jeśli differential tests wykażą zgodność i obecna architektura uniemożliwi bezpieczeństwo/reentrancy.

## 14. Roadmapa zależnościowa

Legenda: **P0** blokuje dalszą pracę, **P1** jest następnym obowiązkowym krokiem, **P2** zależy od potwierdzonego kierunku, **P3** jest opcjonalne. **XS/S/M/L/XL** to względny zakres i powierzchnia ryzyka, nie estymacja kalendarzowa.

### Faza 0: ustalenie prawdy

| Priorytet | Zadanie | Rozmiar | Zależności | Ryzyko | Mierzalne done | Wpływ |
|---|---|---:|---|---|---|---|
| P0 | zatwierdzić zakres i semantykę „Dab 0.1 as implemented” | M | ten audyt + decyzje ownera | spór z historyczną wizją | normatywna spec rozstrzyga `nil`, types, calls, classes, errors i Rings | jedna prawda dla testów/docs |
| P0 | jeden reprodukowalny Linux environment | M | wybór Ruby/Premake/toolchain | ukryte host deps | clean checkout→pełny gate jednym poleceniem na dwóch hostach | onboarding i baseline |
| P0 | kanoniczny test gate, w tym RSpec | S | klasyfikacja disabled/pending | ujawni więcej failures | brak cache `.out`; wszystkie taski raportują pass/fail/skip; timeout działa | wiarygodny CI |
| P0 | sklasyfikować wszystkie obecne failures | S | pełny gate | behavior vs bug | każda porażka ma owner decision/test expectation | usuwa niejasność |
| P1 | spec DAB v3 i corpus artifactów | M | inwentarz codeców | wykrycie host-dependent behavior | layout/endianness/limits opisane, fixtures hash-ready | podstawa validatora |
| P1 | ADR: target user, trust boundary i non-goals | XS | decyzja strategiczna | trudna rezygnacja z zakresu | zaakceptowane „dla kogo / czego nie robimy” | chroni roadmapę |

**Brama F0:** nowy contributor uruchamia pełny, jawnie sklasyfikowany suite bez ręcznego debugowania wersji; README nie twierdzi niczego sprzecznego ze spec.

### Faza 1: stabilizacja

| Priorytet | Zadanie | Rozmiar | Zależności | Ryzyko | Mierzalne done | Wpływ |
|---|---|---:|---|---|---|---|
| P0 | naprawić current GCC/Clang blockers i potwierdzone UB | M | characterization tests | latent behavior dependency | GCC+Clang z fatal warnings, ASan/UBSan bez findings na suite | build i safety baseline |
| P0 | bounded little-endian Reader/Writer + preflight verifier | L | DAB v3 spec | format migration | każdy read sprawdza bounds/overflow; malformed corpus odrzucany strukturalnie | bezpieczna granica bytecode |
| P0 | fuzz loader/assembler/VM decoder | M | verifier + sanitizer build | crash volume | trwały fuzz corpus; długi gate bez crash/sanitizer issue | odporność inputu |
| P0 | naprawić `DabValue` ownership/Rule of Five i pointer casts | L | memory contract | zmiana usecounts | leak/overwrite/cycle policy tests; zero disabled leak fixtures bez uzasadnienia | stabilność VM |
| P1 | wspólny structured error model zamiast `assert/exit` | M | trust boundary | szeroki diff | błędne source/bytecode/FFI daje testowalny error, nie abort | diagnostyka |
| P1 | CI Linux GCC/Clang + sanitizer; compile-only macOS/Windows truth | M | reproducible env | platform fallout | każdy target ma jawny supported/unsupported result | portability truth |
| P2 | ograniczyć/wyłączyć raw FFI w untrusted mode | M | capability decision | łamie examples | default deny; explicit unsafe capability + lifetime tests | zmniejsza impact |

**Brama F1:** żaden obcy `.dabcb` nie jest traktowany jako zaufany; sanitizer/fuzz i pełny suite są zielone, a VM jasno oznacza unsafe mode.

### Faza 2: demonstrator wartości

| Priorytet | Zadanie | Rozmiar | Zależności | Ryzyko | Mierzalne done | Wpływ |
|---|---|---:|---|---|---|---|
| P0 | Ring manifest: input/toolchain/generator hashes + DAG | L | F0 spec, bezpieczny codec | wymusi nowy artifact | manifest jest deterministyczny i walidowany | prawdziwy cache key |
| P0 | typed declaration stubs + source provenance | L | type subset + manifest | obecne metadata są ubogie | arg/return/static/source przechodzą N→N+1 i mają negative tests | statyczna widoczność |
| P0 | hermetyczny evaluator/capabilities | L | trust model | historyczne generators przestaną działać | undeclared file/network/time access failuje | reprodukowalność |
| P0 | flagowe schema demo | M | trzy zadania wyżej | może nie pobić prostego codegen | spełnia siedem kryteriów z §13.2 | proof of value |
| P1 | benchmark przeciw zwykłemu generatorowi pliku | S | demo | negatywny wynik | zapisane build graph, cache hits, diagnostics i UX comparison | uczciwa walidacja |
| P1 | niezależny walkthrough przez nowego contributora | S | docs/demo | brak zainteresowanego | osoba spoza autora odtwarza demo i raportuje friction | contributor signal |

**Brama F2:** jeśli dwa clean builds nie są identyczne, invalidation jest błędna albo zwykły generator daje równy/lepszy UX bez istotnej straty, przejść do scenariusza A.

### Faza 3: konsolidacja architektury

| Priorytet | Zadanie | Rozmiar | Zależności | Ryzyko | Mierzalne done | Wpływ |
|---|---|---:|---|---|---|---|
| P1 | `CompilationSession` zamiast Ruby globals | L | zielony differential suite | pass ordering regressions | dwie kompilacje równolegle/izolowanie dają ten sam wynik | reentrancy |
| P1 | jawne Source AST → typed IR → bytecode IR | XL | Dab 0.1 + pass traces | największy compiler refactor | każdy pass ma input/output invariants i serializer/debug dump | modularność |
| P1 | `DabVM&` context zamiast `$VM` singleton | L | runtime tests | szeroki native diff | dwie VM w jednym procesie, niezależne symbols/heaps | embedding/testability |
| P1 | split loader/interpreter/value/FFI | L | bounded reader + VM context | ABI coupling | moduły mają małe publiczne interfaces i unit tests | maintainability |
| P2 | module/namespace minimum tylko dla demo/product need | L | target use case | scope creep | dwa packages bez collision, explicit imports | skalowanie kodu |
| P2 | libffi/IDL + RAII tylko jeśli FFI pozostaje w scope | L–XL | memory model + platform target | portability | signatures generated from one typed schema; lifetime tests | bezpieczniejszy interop |

### Faza 4: rozwój produktu lub eksperymentu

| Priorytet | Zadanie | Rozmiar | Zależności | Ryzyko | Mierzalne done | Wpływ |
|---|---|---:|---|---|---|---|
| P1 | wybrać dokładnie jeden produkt: research DSL **albo** embedded VM | S | zewnętrzny wynik F2 | rozszczepienie scope | publiczny charter i use-case backlog | focus |
| P1 | Ring explorer: manifest, DAG, generated API, provenance | L | stable manifests | tooling cost | użytkownik widzi „dlaczego symbol istnieje” i invalidation | realna przewaga UX |
| P2 | package/release format dla wybranej niszy | L | module/artifact model | ecosystem cold start | wersjonowany release + konsumujący sample | dystrybucja |
| P2 | rozszerzać stdlib wyłącznie pod flagowy workload | M–L | target user evidence | kopiowanie Ruby | każde API ma aktywnego konsumenta i tests | używalność bez rozlania |
| P3 | performance work po profilach | zależny | reprezentatywny workload | premature optimization | publiczny benchmark i profil przed/po | mierzalna wydajność |

### 14.1 Zrobić teraz / później / nie robić / najpierw udowodnić

**Zrobić teraz**

- zamrozić truth table Dab 0.1;
- odtworzyć jeden clean build i pełny test gate;
- naprawić current compiler blockers, Rings abort i RSpec failure;
- włączyć ASan/UBSan oraz bounded bytecode reader;
- oznaczyć VM/FFI jako trusted-only do czasu F1.

**Zrobić później**

- split AST/IR;
- usunąć globals i singleton;
- moduły minimalne dla potwierdzonego use case;
- Ring explorer/IDE integration;
- uporządkowane FFI tylko jeśli target tego wymaga.

**Nie robić**

- nowych operators, syntax sugar, collections i language features przed F2;
- LLVM/native backend bez profilu;
- pełnego rewrite;
- package managera przed modules/release contract;
- marketingu „general-purpose / highly optimized”.

**Najpierw udowodnić, potem inwestować**

- że Rings dają przewagę nad zwykłym codegen;
- że snapshots mogą być deterministyczne i małe;
- że typed stubs/source provenance są wystarczające dla IDE;
- że ktoś poza autorem potrafi utrzymać pipeline;
- że istnieje choć jedna grupa użytkowników chcąca tego modelu.

## 15. Macierz ryzyka

Skala wykrywalności: **niska** oznacza, że problem może długo pozostać ukryty; **wysoka** — że obecne/planowane sygnały wykryją go szybko.

| Ryzyko | Prawdopodobieństwo | Wpływ | Wykrywalność dziś | Możliwość ograniczenia |
|---|---|---|---|---|
| zależność od autora / bus factor 1 | wysokie | krytyczny | wysoka | ADR, onboarding, zewnętrzny walkthrough, maintainer docs |
| starzenie zależności | wysokie | wysokie | wysoka dopiero przy clean build | pin+hash, regularny CI, supported versions |
| brak użytkowników | wysokie | krytyczny strategicznie | średnia | F2 demo + interviews/usage telemetry, stop gate |
| brak bibliotek | wysokie | wysokie | wysoka | zawęzić use case; nie kopiować ogólnej stdlib |
| konkurencja nowoczesnych języków | wysokie | wysokie | wysoka | pozycjonować Rings research, nie „lepszy C/Ruby” |
| koszt toolingu | wysokie | wysoki | średnia | manifest-first, jedno demo, nie budować IDE od zera |
| złożoność implementacji | wysokie | krytyczny | niska–średnia | jawne invariants, phases, małe bramki |
| niejasna grupa docelowa | wysokie | krytyczny | wysoka | charter i non-goals w F0 |
| wieczny eksperyment | wysokie | wysoki | średnia | F2 stop criteria, releases i outcome metrics |
| rewrite trap | umiarkowane–wysokie | krytyczny | wysoka | differential tests i wymiana tylko jednej granicy |
| feature expansion przed stabilizacją | wysokie | wysoki | wysoka | freeze syntax do F2 |
| optymalizacja przed poprawnością | umiarkowane | wysoki | średnia | sanitizer/validator przed performance |
| VM malformed-bytecode vulnerability | wysokie | krytyczny | niska dziś | bounded reader, verifier, fuzz, trusted-only |
| FFI memory/lifetime vulnerability | wysokie | krytyczny | niska dziś | capability gate, typed ABI, RAII, sanitizer |
| ARC leaks/cycles/corruption | wysokie | wysoki | niska dziś | memory model, leak tests, GC/ARC decision |
| nondeterministic/stale Rings | wysokie | krytyczny dla wyróżnika | niska dziś | content hashes, DAG, hermetic evaluator |
| artifact/ABI portability | wysokie | wysoki | niska przez Linux-only CI | canonical LE codec i platform matrix |
| specialisation code explosion/wrong semantics | umiarkowane | wysoki | niska | guards, fallback equivalence, budgets |
| false confidence from goldens | wysokie | wysoki | średnia | property/negative/fuzz/sanitizer tests |
| source provenance loss | wysokie | średni–wysoki | wysoka dla użytkownika dopiero późno | typed manifest + origin spans |

## 16. Oceny 0–10

| Kategoria | Ocena | Krótkie uzasadnienie |
|---|---:|---|
| wartość obecnego kodu jako bazy | 5 | pełny pionowy prototyp i corpus, ale niebezpieczny runtime i sprzeczna semantyka |
| jakość architektury | 4 | koncepcyjnie czytelny pipeline, słabe granice, globals i silne ABI coupling |
| jakość designu języka | 5 | ciekawa wizja `T/T?/T!` + Rings, lecz nierozstrzygnięte konflikty dynamiki i stagingu |
| unikalność | 6 | kombinacja executable serialized Rings jest charakterystyczna, primitives są znane |
| kompletność | 3 | wiele powierzchni istnieje, podstawy modules/errors/memory/types są niedomknięte |
| niezawodność | 2 | clean build fail, test crash/failure/hang i potwierdzone UB |
| developer experience | 2 | przestarzałe instrukcje, brak bootstrapu, wiele kroków, mylący `spec` |
| dokumentacja | 3 | design intent i generated docs istnieją, lecz najważniejsze twierdzenia są nieaktualne |
| zdolność do modernizacji | 5 | fixtures i małe opcode pomagają; bus factor/coupling/memory model przeszkadzają |
| potencjał edukacyjny | 8 | niezwykle szeroki przekrój compiler→VM→tools w relatywnie małym repo |
| potencjał badawczy | 7 | Rings i cross-stage persistence dają konkretne pytania eksperymentalne |
| potencjał jako realne narzędzie | 2 | możliwy dopiero po F1/F2 i radykalnym zawężeniu |
| potencjał zdobycia contributorów | 3 | ciekawy temat, lecz bardzo wysoki próg i brak aktywnego procesu |
| potencjał zdobycia użytkowników | 2 | brak obecnej niszy/ekosystemu; szansa tylko przez przekonujące demo Rings |

## 17. Prognozy

### Optymistyczna

Owner akceptuje zawężenie, F0/F1 porządkują build i runtime, a schema demo pokazuje typed, reprodukowalne generated API z lepszą invalidation/provenance niż prosty generator. Projekt zdobywa małą grupę compiler/DSL contributors i staje się wiarygodnym research artifact lub niszowym DSL toolkit. Prawdopodobieństwo: **niskie–umiarkowane**, bo wymaga konsekwentnego ograniczania zakresu.

### Realistyczna

Da się odtworzyć build, zabezpieczyć część loadera i opublikować uczciwy Dab 0.1. Rings pozostaną interesującym, lecz ciężkim demonstratorem; nie powstanie general-purpose ecosystem. Najlepszym wynikiem będzie dobrze zachowane laboratorium z jednym reproducible demo i materiałem edukacyjnym. Prawdopodobieństwo: **umiarkowane**, jeśli istnieje aktywny maintainer; bez niego niskie.

### Pesymistyczna

Prace rozproszą się na nowe features lub rewrite, build nadal będzie zależny od starego toolchainu, a bezpieczeństwo VM pozostanie nieadresowane. Brak zewnętrznego użytkownika odbierze priorytet i repo ponownie zamarznie, tym razem z dwiema niedokończonymi implementacjami. Prawdopodobieństwo: **umiarkowanie wysokie** przy kontynuacji historycznego, szerokiego scope.

### 17.1 Decyzja po demonstratorze

- **Kontynuować**, gdy F0/F1 są zielone, demo spełnia wszystkie kryteria, a co najmniej jeden niezależny użytkownik potwierdza przewagę.
- **Zawęzić jeszcze bardziej**, gdy mechanizm jest technicznie ciekawy, ale nie uzasadnia języka; wydzielić spec/codec/Ring research artifact.
- **Zarchiwizować**, gdy nie da się uzyskać deterministycznego Ring, bezpiecznej granicy bytecode lub niezależnego clean builda.

## 18. Lista najważniejszych działań

### 18.1 Dziesięć działań w kolejności

1. **Zatwierdzić charter i non-goals:** „staged metaprogramming laboratory”, trusted-input only do czasu F1, brak nowych features.
2. **Zamrozić normatywny Dab 0.1:** testy i kod rozstrzygają status quo, a każda świadoma zmiana semantyki ma ADR.
3. **Dostarczyć jeden clean, pinned build:** Ruby, Bundler, Premake checksum, GCC/Clang i jedno polecenie.
4. **Uczynić pełny gate prawdziwym:** włączyć RSpec, naprawić `readbin`, Rings stale-index crash, formatter failure i egzekwowany timeout.
5. **Spisać DAB v3 i zastąpić raw reads bounded verifierem:** canonical little-endian, limits, version rejection.
6. **Uruchomić sanitizer/fuzz campaign i naprawić potwierdzone UB:** loader, `DabValue`, Buffer, casts, builtins.
7. **Podjąć jawną decyzję memory/FFI:** trusted unsafe mode teraz; docelowo GC albo kompletne ownership/ARC, typed ABI/capabilities.
8. **Zaprojektować minimalny Ring manifest:** DAG, hashes, typed signatures, source provenance i declared inputs.
9. **Zbudować oraz porównać schema demo z prostym codegen:** identyczność, invalidation, cache hit, diagnostics i onboarding.
10. **Wykonać bramkę decyzyjną z osobą spoza autora:** kontynuować D, punktowo wymienić VM/codec, albo zarchiwizować A.

### 18.2 Dziesięć najważniejszych problemów technicznych

1. Loader `.dabcb` nie waliduje granic, overflow, section/count/address przed raw access.
2. `DabValue` łamie ownership przy zwykłym overwrite i nie rozwiązuje cykli.
3. Pointer/String/ByteBuffer casts tworzą dangling/unbounded/OOB ścieżki.
4. Format binarny i jump fixups są częściowo host-endian i nie mają normatywnych limitów.
5. Rings `bin_save` crashuje na aktywnym multilevel fixture z powodu stale vector index.
6. Rings importują nazwę/placement, ale odrzucają typed signature i source origin.
7. Compiler i VM są globalne/singleton, niereentrant i trudno testowalne.
8. AST, SSA, typy, formatter i codegen współdzielą jeden mutowalny graf.
9. Domyślny build/test pipeline jest nieodtwarzalny, niepełny i obecnie czerwony.
10. FFI jest ad hoc, POSIX-only, bez ownership/RAII i z potwierdzoną niespójną sygnaturą.

### 18.3 Pięć najcenniejszych cech

1. Prawdziwy source→bytecode→VM vertical slice.
2. Executable/serializable Rings i ponowne importowanie wygenerowanych symboli.
3. Bogaty characterization corpus assemblera, VM i compiler behavior.
4. Mały, generowany model opcode z kompletem narzędzi wokół formatu.
5. Widoczne SSA/lowering/fixed-point passes jako materiał badawczy i edukacyjny.

### 18.4 Pięć elementów do usunięcia, uproszczenia lub zamrożenia

1. **Zamrozić** nowe syntax/language features do przejścia F2.
2. **Usunąć z komunikacji** „general-purpose”, „highly optimized” i zaimplementowane `T?`/`T!`.
3. **Uprościć** Ring output z niejawnego obrazu do wersjonowanego manifestu + minimalnego artifactu.
4. **Usunąć/domknąć** host-native binary reads i duplicated raw layout; jedno canonical codec API.
5. **Zamrozić raw FFI jako explicit unsafe/trusted-only**; nie rozszerzać signature ladder.

### 18.5 Pięć szybkich eksperymentów walidacyjnych

1. **Reproducibility:** dwa isolated clean builds flagowego Ring, byte-for-byte diff i hash manifestu.
2. **Invalidation:** zmienić app-only, schema-only i generator-only; porównać dokładne rebuilt nodes/cache hits.
3. **Codegen A/B:** ten sam schema DSL przez Ring i zwykły generator pliku; zmierzyć kroki, czas, diagnostics, IDE metadata.
4. **Malformed corpus:** truncate/flip/count-overflow każdej sekcji DAB pod ASan/UBSan/fuzzer; oczekiwany structured reject.
5. **Reentrancy spike:** uruchomić dwie minimalne VM i dwie compilation sessions w jednym procesie; skatalogować global dependencies przed refaktorem.

### 18.6 Pięć pytań strategicznych do właściciela

1. Czy celem jest badanie Rings, zachowanie historyczne, czy narzędzie dla konkretnego użytkownika — który jeden ma pierwszeństwo?
2. Czy zgodność z obecnym zachowaniem jest ważniejsza niż zamierzona semantyka README, zwłaszcza dla `nil` i types?
3. Czy kod Ring może wykonywać dowolne FFI/I/O, czy reprodukowalność i sandbox są nadrzędne?
4. Czy VM ma wykonywać niezaufany bytecode i być embeddable, czy wyłącznie lokalny trusted artifact compiler?
5. Jakie jedno zewnętrzne zachowanie po F2 uzasadni dalszą inwestycję, a jaki wynik zakończy projekt?

### 18.7 Jedno flagowe demo

**`schema.json` → Ring generator → typed model/query API → aplikacja** z compile-time rejection nieistniejącego pola, source provenance do schema, deterministycznym artifact SHA oraz poprawnym cache hit/invalidation. Szczegółowe kryteria są w §13.2. Demo nie wymaga sieci, bazy danych ani raw FFI.

### 18.8 Minimalna definicja Dab 0.1

To ma być **specyfikacja stanu, nie lista życzeń**:

| Element | Dab 0.1 |
|---|---|
| Implementacja referencyjna | obecny Ruby compiler + DAB v3 + C++ VM po F1 |
| Platforma | początkowo Linux x86_64, dokładnie dwa toolchainy; inne jawnie unsupported |
| Pliki | wiele `.dab` scalanych do jednej globalnej compilation unit; brak modułów/importów |
| Składnia rdzenia | funkcje, klasy z pojedynczym dziedziczeniem, locals, calls/methods, `if`, `while`, literals, arrays i blocks |
| Typy | dynamiczny `Object` fallback; adnotacje tylko dla jawnie wymienionych builtinów; brak claimu sound gradual typing |
| `nil` | dokumentować realne bieżące assignment behavior do czasu świadomej breaking decyzji |
| Poza 0.1 | `T?`, źródłowe `T!`, user-class types, generics, modules, exceptions, native codegen |
| Specjalizacja | opcjonalna optymalizacja global calls; generic i specialized muszą być obserwowalnie równoważne |
| Pamięć | tylko po zdefiniowaniu ownership/GC; do tego czasu runtime experimental, nie long-lived production |
| FFI | explicit unsafe i trusted local programs; brak gwarancji Windows |
| Rings | experimental opt-in; widoczność nazw w kolejnym etapie, bez obietnicy cache/IDE do F2 |
| Bytecode | wersjonowany DAB v3, canonical LE, bounded verifier, hard limits i clear unsupported-version error |
| Tooling | compiler, assembler, VM, disasm; formatter/decompiler oznaczone jako partial/non-round-trip |
| Jakość wydania | clean build, pełny suite + sanitizers, known issues i reproducible artifact |

### 18.9 Kryteria „kontynuować, zawęzić czy zarchiwizować”

| Decyzja | Wymagane dowody |
|---|---|
| **Kontynuować** | F0/F1 zielone; demo deterministyczne; poprawna invalidation; typed provenance; niezależny użytkownik widzi przewagę nad codegen |
| **Zawęzić** | codec/VM albo Ring manifest ma wartość, lecz pełny język nie; wydzielić research artifact/DSL i zamrozić resztę |
| **Zarchiwizować** | brak maintainer ownership, clean build nadal kruchy, verifier/memory safety niewykonalne w scope, Rings niedeterministyczne albo A/B przegrywa |

## 19. Załącznik z dowodami

### 19.1 Ledger kodu, symboli i linii

| Teza | Plik / symbol / linie | Co bezpośrednio potwierdza |
|---|---|---|
| projekt sam określa się jako prototyp | `README.md:1-7` | „Very early prototype”, Ruby compiler/assembler, C++ VM |
| szeroka wizja i typy są deklaracją | `README.md:13-29` | low→high level, inference, specialization, `T/T?/T!` |
| Rings claim | `README.md:31-57`; `docs/design/rings.md` | layered metaprogramming, static visibility i cache jako zamiar |
| podstawowe braki są znane | `TODO.md:5-11,20,23-31,36-49,67-79` | nullable/final, ARC, exceptions, invalidation, namespaces, endian/native |
| oficjalny build jest stary | `docs/building.md:6-15,34-47` | Ruby 2.3, Premake alpha11, last revised 2017 |
| build graph i default tasks | `Rakefile:21-188,190-236,250-269` | generators/native builds/stdlib/test families; RSpec nie jest default |
| fatal compiler warnings | `premake5.lua:12-16,22-28` | C++11, Extra warnings, FatalCompileWarnings |
| input i Ring merge | `DabCompilerFrontend#run`, `parts/main.rb:19-79` | load bases, parse wszystkich source files |
| compiler pass order | `parts/main.rb:83-150,195-273` | init loops, checks, SSA, optimize/lower/flatten fixed point |
| 17 callback classes | `parts/module_processors.rb:1-102,182-247` | dynamic phase registry i traversal |
| scanner i diagnostics | `shared/parser.rb:21-52,57-111,136-486` | char positions, line annotation, lexical reads |
| top-level grammar | `parts/context.rb:52-71` | wyłącznie funcs/classes |
| type syntax | `parts/context.rb:101-139,550-569` | pojedynczy identifier w `<...>` |
| class/templates/parent parser | `parts/context.rb:142-179,521-537` | syntax istnieje, bez pełnej semantyki |
| blocks/closures syntax | `parts/context.rb:580-622` | `^`, args i block node |
| AST responsibilities | `nodes/node.rb:4-323` | ownership/cache/source/errors/replacement/compile |
| type whitelist i `nil` | `parts/types.rb:2-25,250-297` | builtins; każdy zwykły typ przyjmuje Nil/Object; internal concrete `!` |
| niedefiniowany typed ByteBuffer | `parts/types.rb:18`; brak klasy w wyniku repo-wide `rg` | annotation `ByteBuffer` prowadzi do brakującej stałej Ruby |
| specjalizacja | `processors/concreteify_call.rb:1-23`; `nodes/node_function.rb:259-274` | warunki i cloning `__name_Types` |
| function/class emission | `nodes/node_unit.rb:174-284` | DAB v3 sections i sorted bodies/metadata |
| multi-file merge | `parts/main.rb:58-75`; `node_unit.rb:310-329` | wspólna unit i Ring merge |
| opcode ABI | `shared/opcodes.rb:20-129,146-173` | real/pseudo opcode, kernel syscalls, reflection |
| assembler encoding | `tobinary.rb:120-161,188-257,316-403` | native `S/s`, LE 32/64, header, section/fixup |
| binary structs/unsafe reads | `cshared/stream.h:52-117,215-222`; `stream.cpp:3-48` | packed layout, assert/type-pun reads |
| loader trust | `cvm/bin_load.cpp:3-305` | section/function/class/symbol counts i raw addresses |
| Buffer allocator mismatch | `cshared/buffer.cpp:19-38` | `malloc` kontra `delete[]` |
| singleton VM | `cvm/main.cpp:7-25`; `cvm.h:691-695` | global `$VM` i single-instance assert |
| interpreter | `cvm/main.cpp:504-972` | giant opcode dispatch |
| template collision | `cvm/main.cpp:778-804` | hardcoded class index 4096 |
| pointer cast hazards | `cvm/main.cpp:1088-1131` | temporary c_str, strdup, vector pointer i unbounded String |
| ARC overwrite leak | `cvm/dab_value.cpp:487-518`; `main.cpp:90-91,403-416` | ordinary register/ivar overwrite reaches leaking assignment |
| unchecked builtins | `cvm/default_classes.cpp:122-141,205-213,267-278`; `defaults_shared.h:6-62` | OOB String/Array/ByteBuffer i arithmetic UB |
| FFI loader | `cvm/syscalls.cpp:52-122` | arbitrary `dlopen`/`dlsym`, no close, broken Windows branch |
| FFI signature mismatch | `cvm/ffi_signatures.h:247-259`; `cvm.h:339-344` | CLASS_STRING return kontra DynamicString assert |
| Ring import | `compiler/parts/readbin.rb:1-202` | binary sections→class/function/symbol stubs |
| Ring traci signatures | `readbin.rb:41-50,114-140`; `node_function_stub.rb:6-9,28-30` | metadata odczytane, lecz stub ma Object/no args contract |
| Ring execution loop | `frontend/frontend_multidab.rb:27-72` | compile→assemble→execute dump→next base |
| dynamic methods | `cvm/define_method.cpp:4-234` | C++ synthesizes bytecode; limited captured values |
| multilevel crash | `cvm/bin_save.cpp:117-159` | indeksy policzone przed erase i użyte po shrink |
| formatter | `frontend/frontend_format.rb:13-20`; node `formatted_source` methods | parse/print, nie semantic round-trip |
| coverage | `node_unit.rb:181-213`; `cvm/coverage.cpp:3-35`; `cov/cov.rb:20-82` | opcode instrumentation→line report |
| decompiler limits | `decompile/decompile.rb:26-155,193-235` | obsługiwany podzbiór, unknown op i parent TODO |
| CI scope | `.github/workflows/ruby.yml:19-40` | Ubuntu-only Ruby matrix, default rake, no RSpec/sanitizers |
| fake timeout | `shared/system.rb:120-127` | informacyjny timeout bez process enforcement |
| ORM OOB | `examples/0004_orm/level1/orm.dab:63-68` | `2L` destination i `2L` input length dla PQescapeString |

### 19.2 Polecenia i wyniki

Wszystkie build/test commands poza prostą inspekcją Git wykonano w izolowanym checkoutcie `/tmp/dablang-audit.9vtZ1T`. Główny checkout nie był używany jako katalog builda. Host: Ubuntu 26.04 LTS x86_64, kernel 7.0.0-27, glibc 2.43, GCC/G++ 15.2.0, Clang 21.0.0 i Make 4.4.1; testowe Ruby 3.3.12 wobec pinu repo 3.1.6.

| Polecenie | Wynik |
|---|---|
| `git status --short` przed audytem | pusty |
| `git rev-parse HEAD` | `6bd31971f4264cb30b0719dddfba55dee62889da` |
| `git ls-remote origin refs/heads/master` | ten sam SHA |
| `git rev-list --count HEAD` | 2492 |
| `git rev-list --merges --count HEAD` | 0 |
| `git tag --list` | pusty |
| `git shortlog -sne HEAD` | 2100 + 387 głównych tożsamości, 4 bot, 1 alternate |
| `git ls-files \| wc -l` | 825 |
| `git ls-files \| xargs wc -l` | 47 686 total lines |
| `find stdlib -name '*.dab' ... \| wc -l` | 286 linii |
| `bundle exec rake` | rbenv: Ruby 3.1.6 nie jest zainstalowane; nic nie zbudowano |
| `RBENV_VERSION=3.3.12 BUNDLE_PATH=... bundle install` | success, 13,97 s |
| `PREMAKE=./premake5 bundle exec rake` z GCC 15 | fail `format-truncation`, `cdisasm/disasm.cpp:363`, 11,27 s |
| odpowiedni clean build z Clang 21 | fail dangling pointer, `cvm/main.cpp:1092`, 11,72 s |
| GCC + `CXXFLAGS=-Wno-error=format-truncation` + default rake | 443 znane fixture’y przed abortem `multidab/0002`; fail po 101,36 s |
| `bundle exec rspec --seed 2297` | 70 examples: 53 pass, 1 failure, 16 pending; 1,34 s |
| `bundle exec rake -B decompile_spec` | 24/24 pass; 13,05 s |
| `bundle exec rake -B compiler_performance_spec` | 2/2 pass; 2,10 s |
| `timeout --kill-after=5s 35s ... rake -B build_examples_spec` | nadal kompilował database example; exit 124; 35,20 s |
| locked `bundle exec rubocop` | 217 files, 0 offenses; 15,43 s |
| `rake format:stdlib_check` | fail `stdlib/array.dab:85` |
| `rake format:sort_check` | pass |
| `rake format:cpp_check` | fail: `clang-format` brak w PATH |
| `bundle outdated --parseable` | 20 outdated direct/transitive packages |
| Ruby 4.0.5: locked `bundle install` + RSpec | bundle success; ten sam bilans 53/1/16, więc brak nowej wykrytej niezgodności |
| public GitHub Actions workflow query | aktywny workflow, `total_count: 0` zachowanych runs |

Pełne logi robocze i zbudowane artefakty pozostawiono w `/tmp/dablang-audit.9vtZ1T` na czas tej sesji; nie są one częścią repo ani trwałym dowodem release.

### 19.3 Test corpus — statyczne liczniki

```text
test/dab:                  240 aktywnych .dabt + 6 disabled .dabtx
test/asm:                  102
test/vm:                    35
test/format:                31
test/decompile:             24 aktywne + 1 disabled
test/multidab:              12 aktywnych + 1 disabled
test/disasm:                10
test/debug:                  7
test/minitest:               5
test/dumpcov:                2
test/cov:                    1
test/compiler_performance:   2
spec:                       23 *_spec.rb; 16 xit
```

W `test/dab` znajduje się 16 przypadków `EXPECT COMPILE ERROR`. FFI ma dwa pozytywne fixtures. Dedykowane parser specs obejmują trzy przypadki komentarzy. Nie znaleziono konfiguracji fuzzerów ani sanitizer CI.

### 19.4 Historia i churn

Polecenia użyte do historii obejmowały `git log --format=%cI`, `git shortlog -sne`, `git rev-list --count`, `git log --numstat -- <path>` i `git rev-list --left-right --count master...origin/<branch>`. Najbardziej historycznie zmienne pliki:

| Plik | File touches | Znaczenie |
|---|---:|---|
| `src/cvm/main.cpp` | 436 | interpreter/CLI/casts/global VM |
| `src/cvm/cvm.h` | 317 | centralne runtime types/state |
| `src/cshared/opcodes.h` | 138 | generowane ABI |
| `src/compiler/parts/context.rb` | 150 | gramatyka/scope/AST |
| `src/cvm/default_classes.cpp` | 146 | native stdlib semantics |
| `src/cvm/dab_value.cpp` | 115 | ownership/value model |
| `src/cvm/bin_save.cpp` | 41 | Ring snapshot |
| `src/cvm/bin_load.cpp` | 23 | trusted binary boundary |

Churn nie dowodzi błędu sam w sobie; w połączeniu z rozmiarem, global state i brakiem pełnych testów wskazuje miejsca najwyższego regression risk.

### 19.5 Źródła zewnętrzne użyte do porównań i stanu narzędzi

- [Ruby downloads](https://www.ruby-lang.org/en/downloads/) — wspierane/current linie Ruby.
- [Premake releases](https://github.com/premake/premake-core/releases) — aktualność beta2.
- [actions/checkout releases](https://github.com/actions/checkout/releases) — aktualność action.
- [Rust procedural macros](https://doc.rust-lang.org/stable/reference/procedural-macros.html) — compile-time token transform i security model.
- [Zig `comptime`](https://ziglang.org/documentation/master/#comptime) — jawne compile-time-known values/types.
- [Nim Manual](https://nim-lang.org/docs/manual.html) — interleaving semantic analysis i compile-time execution.
- [Crystal macros](https://crystal-lang.org/reference/1.20/syntax_and_semantics/macros/index.html) — AST-in/code-out.
- [Julia metaprogramming/generated functions](https://docs.julialang.org/en/v1/manual/metaprogramming/#Generated-functions) — type specialization, purity i cache restrictions.
- [Racket phase levels](https://docs.racket-lang.org/guide/phases.html) — oddzielne environments/bindings per phase.
- [GHC Template Haskell](https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/template_haskell.html) — stages, levels i cross-stage persistence.
- [Elixir macros](https://hexdocs.pm/elixir/main/macros.html) — lexical/hygienic/explicit macros.
- [GraalVM Truffle](https://www.graalvm.org/jdk22/graalvm-as-a-platform/language-implementation-framework/) — self-modifying AST interpreters i partial evaluation.
- [LuaJIT](https://luajit.org/luajit.html) — trace specialization/JIT.
- [Kotlin/Native C interop](https://kotlinlang.org/docs/native-c-interop.html) — header-driven typed bindings/lifetimes.
- [PostgreSQL `PQescapeString` contract](https://www.postgresql.org/docs/16/libpq-exec.html) — dowód rozmiaru bufora w ORM example.

### 19.6 Mapa wymagań audytu

| Etap zlecenia | Główna sekcja raportu |
|---|---|
| 1. mapa projektu | §3 |
| 2. stan implementacji języka | §4 |
| 3. jakość techniczna | §7, §9–10 |
| 4. testy i wiarygodność | §5.2–5.5 |
| 5. build/tooling/DX | §5.1, §5.6–5.7 |
| 6. analiza idei | §8.1–8.4, §11 |
| 7. unikalność i pozycjonowanie | §8.5–8.6 |
| 8. mocne/słabe/niedocenione/przecenione | §6–7 |
| 9. problemy naprawialne/fundamentalne | §9–10 |
| 10. scenariusze A–D | §12 |
| 11. rekomendowany kierunek | §13 |
| 12. roadmapa F0–F4 | §14 |
| 13. oceny i prognozy | §16–17 |
| 14. zagrożenia | §15 |
| 15. konkretne działania | §18 |

### 19.7 Ostateczna klasyfikacja pewności

- **Potwierdzone fakty:** architektura, braki typów, działanie/niedziałanie testów, current build blockers, wskazane memory/loader bugs, historia Git.
- **Mocne przesłanki:** bus factor 1, brak realnej general-purpose viability, najlepsze pozycjonowanie research/education.
- **Hipotezy:** możliwa przewaga hermetycznych Rings, możliwość RCE z malformed bytecode, zainteresowanie niszowych użytkowników.
- **Niezweryfikowane:** macOS/Windows runtime, pełny performance profile, complete exploitability, reakcja użytkowników i koszt migracji na nowy memory model.
