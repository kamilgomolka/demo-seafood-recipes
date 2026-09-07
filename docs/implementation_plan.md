# Meal Recipes — plan implementacji

Status: zaimplementowane. Dokument przeniesiony z `./PLAN.md` do `./docs/implementation_plan.md`. Kryteria z sekcji 12, które wymagają builda i testów, są potwierdzane w CI / lokalnym `make test`, nie samym istnieniem kodu.

## 1. Cel edukacyjny

Mała, działająca aplikacja ma pokazywać prawidłowe użycie SwiftUI i Swift Concurrency przy pobieraniu danych z sieci. Priorytetami są:

- własność i trwałość modelu względem tożsamości widoku;
- Observation i renderowanie interfejsu na podstawie stanu;
- izolacja `MainActor` oraz przekazywanie wartości przez granice izolacji;
- bezpośrednie wywołania `async/await`, zawieszanie pracy i kooperatywne anulowanie;
- zachowanie przy ponownym wejściu, odświeżaniu i błędach;
- deterministyczne testowanie zachowań asynchronicznych.

Każda warstwa i mechanizm muszą wynikać z tego przepływu. Projekt nie obejmuje wyszukiwania, szczegółów, paginacji, ulubionych, persystencji, własnego cache obrazów ani dodatkowych ekranów demonstracyjnych w aplikacji produkcyjnej.

## 2. Stack i konfiguracja

- SwiftUI i frameworki Apple, bez zależności zewnętrznych.
- iOS 26.0+, wyłącznie iPhone, orientacja portrait.
- Tryb języka Swift 6 (`SWIFT_VERSION = 6.0`).
- Zachowane domyślne izolowanie kodu aplikacji do `MainActor` i Approachable Concurrency.
- Pełna kontrola concurrency przez kompilator; build bez ostrzeżeń.
- Observation do obserwowania modelu, Swift Testing do unit testów, XCTest do UI testów.

`Swift 6.0` oznacza tutaj tryb języka, a nie wymóg kompilacji kompilatorem 6.0. `@concurrent` wymaga kompilatora Swift 6.2 lub nowszego. Lokalnie dostępny jest Swift 6.3.3. README wskaże wymaganie toolchainu oddzielnie od deployment targetu.

## 3. Zachowanie aplikacji

Ekran startowy od razu pokazuje listę przepisów kategorii `Seafood` z TheMealDB. Każdy wiersz zawiera nazwę oraz miniaturę. Wiersze nie mają akcji ani nawigacji.

| Sytuacja | Zachowanie |
| --- | --- |
| Pierwsze wejście | Automatyczne pobranie i wskaźnik ładowania |
| Poprawna odpowiedź | Lista z identyfikatorami pochodzącymi z API |
| Pusta odpowiedź | Komunikat o braku przepisów; dostępne odświeżenie |
| Błąd pierwszego pobrania | Komunikat i przycisk ponowienia |
| Pull-to-refresh | Widoczna dotychczasowa zawartość; systemowy wskaźnik odświeżania |
| Błąd odświeżenia | Dotychczasowa zawartość oraz komunikat z ponowieniem |
| Anulowanie | Brak komunikatu błędu; zachowanie poprzednich danych |
| Ponowne pojawienie się z danymi | Bez automatycznego pobierania |
| Ponowne pojawienie się po anulowaniu pierwszego pobrania | Ponowna próba automatycznego pobrania |
| Przejście do tła i powrót | Brak dodatkowego pobrania wywołanego przez `scenePhase` |

Przejście aplikacji do tła nie jest utożsamiane z usunięciem widoku. Nie dodajemy działania w tle ani mechanizmu wznawiania sieci przez obserwację fazy sceny.

## 4. Architektura i własność

Małe MVVM, z zależnościami przekazywanymi przez inicjalizatory.

| Element | Odpowiedzialność |
| --- | --- |
| `MealsView` | Renderowanie, zdarzenia użytkownika i integracja z cyklem życia SwiftUI |
| `MealsViewModel` | Stan ekranu, reguły pobierania, przejścia stanu i obsługa wyników |
| `MealsState` | Dozwolone stany zawartości i odświeżania |
| `Meal` | Niezmienny model pojedynczego wiersza |
| `MealService` | Protokół z jedną operacją pobierającą przepisy |
| `MealAPIClient` | Budowa żądania, HTTP, dekodowanie i mapowanie błędów |
| `MealAPIError` | Typowany kontrakt błędów operacji |

Punkt wejścia aplikacji trzyma produkcyjnego `MealAPIClient` i `MealsViewModel` w `@State` (inicjalizacja poza `body`). W Debug wybiera scenariusz testowy z własnym złożeniem. Ekran utrzymuje ViewModel w prywatnym `@State`; ViewModel jest `@MainActor @Observable final class`.

Inicjalizatory są tanie i pozbawione efektów ubocznych. Nie rozpoczynają pobierania. Odtworzenie wartości `View` nie powinno rozpoczynać pracy ani zastępować modelu przechowywanego przez SwiftUI dla tej samej tożsamości ekranu.

ViewModel nie importuje SwiftUI. Udostępnia stan tylko do odczytu oraz metody asynchroniczne do ładowania i odświeżania. Wewnętrzna synchronizacja nie jest obserwowanym stanem UI.

Bezstanowy klient pozostaje strukturą. Nie powstają dodatkowe repozytoria, use case'y, koordynatory, generyczne klienty HTTP ani kontenery DI.

## 5. Model stanu

```swift
enum MealsState {
    case idle
    case loading
    case failed(MealAPIError)
    case loaded([Meal], refresh: RefreshState)
}

enum RefreshState {
    case idle
    case refreshing
    case failed(MealAPIError)
}
```

`loaded([])` oznacza poprawny pusty wynik. Stan odświeżania istnieje wyłącznie razem z wcześniej pobraną zawartością, także pustą.

| Stan początkowy | Zdarzenie | Stan wynikowy |
| --- | --- | --- |
| `idle` | Automatyczne pobranie | `loading` |
| `failed` | Jawne ponowienie | `loading` |
| `loading` | Sukces | `loaded(meals, refresh: .idle)` |
| `loading` | Błąd | `failed(error)` |
| `loading` | Anulowanie | `idle` |
| `loaded` | Odświeżenie lub ponowienie odświeżenia | `loaded(previousMeals, refresh: .refreshing)` |
| Odświeżanie | Sukces | `loaded(newMeals, refresh: .idle)` |
| Odświeżanie | Błąd | `loaded(previousMeals, refresh: .failed(error))` |
| Odświeżanie | Anulowanie | `loaded(previousMeals, refresh: .idle)` |

Pochodne informacje, np. czy trwa pobieranie lub czy wynik jest pusty, wynikają ze stanu. Nie utrzymujemy ich jako osobnych mutowalnych flag.

## 6. Concurrency i cykl życia operacji

### 6.1. Reguła jednego pobierania

Jednocześnie trwa najwyżej jedno pobieranie listy. Kolejne odświeżenie lub ponowienie podczas aktywnego pobierania nie tworzy następnego żądania i nie anuluje poprzedniego. Przyciski ponowienia są wtedy nieaktywne.

Nie stosujemy polityki „najnowszy wynik wygrywa”, identyfikatorów requestów ani kolejki odświeżeń. Parametry zapytania są stałe.

ViewModel sprawdza i ustawia stan operacji na `MainActor` przed pierwszym `await`. Zakończenie, przywrócenie stanu po anulowaniu i zwolnienie operacji odbywają się na tym samym aktorze, bez punktu zawieszenia pomiędzy tymi zmianami.

Automatyczne wejście wymaga dodatkowego rozróżnienia: jeżeli poprzednie pobieranie kończy się po anulowaniu, nowe wejście oczekuje na zakończenie jego sprzątania i ponownie ocenia potrzebę pobrania. Nie może zakończyć się wyłącznie na sprawdzeniu `isLoading`, pozostawiając później ekran w `idle`. Oczekiwanie jest asynchroniczne i nie tworzy drugiego requestu. Synchronizacja pozostaje lokalnym szczegółem funkcji, bez osobnej infrastruktury zarządzania zadaniami.

### 6.2. Pierwsze wejście i ponowienie

Stabilny kontener ekranu otrzymuje `.task(id:)`. Identyfikator zmienia się tylko w odpowiedzi na jawne ponowienie przez użytkownika. Nie zależy od bieżącego stanu ładowania, danych ani losowego UUID tworzonego podczas renderowania.

Akcja `.task` bezpośrednio oczekuje na metodę ViewModelu, a ta bezpośrednio oczekuje na klienta API. ViewModel nie opakowuje pobierania we własny `Task {}`.

Pierwsze wykonanie pobiera tylko wtedy, gdy brakuje wyniku i nie pozostawiono błędu wymagającego jawnego ponowienia. Zmiana identyfikatora przez przycisk retry uruchamia odpowiednią próbę, również po błędzie odświeżenia. Żądanie retry jest zużywane jednokrotnie; ponowne pojawienie się z tym samym identyfikatorem nie oznacza kolejnego wymuszonego odświeżenia.

SwiftUI jest właścicielem tego zadania. Modyfikator pozostaje na kontenerze niezależnym od gałęzi `loading`, `failed` i `loaded`, aby zmiana stanu nie anulowała własnego pobierania.

### 6.3. Pull-to-refresh

`.refreshable` oczekuje na rzeczywiste zakończenie operacji; nie uruchamia pobierania w trybie fire-and-forget.

Nie zakładamy, że `.refreshable` zapewnia identyczne gwarancje anulowania jak `.task`. Dla spełnienia wymagania anulowania po zniknięciu ekranu widok przechowuje uchwyt zadania odświeżenia:

- zadanie służy wyłącznie powiązaniu tej akcji z życiem ekranu;
- `.refreshable` oczekuje na jego zakończenie;
- anulowanie akcji wywołującej jest jawnie przekazywane do tego konkretnego zadania;
- `onDisappear` anuluje zadanie odświeżenia;
- uchwyt jest zwalniany po zakończeniu; sprzątanie dotyczy wyłącznie kończącego się zadania;
- aktywne odświeżenie nie jest zastępowane nowym.

To kontrolowane zadanie niestrukturalne na granicy UI. Powód jego istnienia zostanie opisany w README. ViewModel i klient nadal oferują zwykłe operacje `async`, bez przechowywania uchwytów zadań.

### 6.4. Anulowanie i ponowne wejście

- Sprawdzenie anulowania przed rozpoczęciem pracy zapobiega wysyłaniu już anulowanego żądania.
- Sprawdzenie po oczekiwaniu i przed publikacją wyniku zapobiega przyjęciu sukcesu zwróconego mimo anulowania.
- Anulowanie ma pierwszeństwo przed prezentacją błędu otrzymanego przez anulowaną operację.
- Przywrócenie stanu po anulowaniu następuje przed dopuszczeniem kolejnego pobierania.
- Nowe wejście nie może zostać zablokowane przez spóźnione sprzątanie wcześniejszej operacji.
- Nie blokujemy wątku ani aktora semaforami, synchronicznym oczekiwaniem lub pollingiem.

Szybkie zniknięcie i ponowne pojawienie się ekranu jest obowiązkowym przypadkiem weryfikacji, obejmującym również zależność, która nie reaguje natychmiast na anulowanie.

### 6.5. Granice izolacji

- ViewModel i mutacje stanu: `MainActor`.
- Model wiersza, klient i wartości przekraczające granice izolacji: niemutowalne typy `Sendable`.
- Protokół klienta i typy dekodowane: jawnie dobrana izolacja, umożliwiająca użycie poza `MainActor` przy ustawieniach tego projektu.
- Operacja produkcyjnego klienta: `@concurrent`, obejmujące przygotowanie odpowiedzi i dekodowanie poza aktorem wywołującym.
- `JSONDecoder` tworzony lokalnie dla operacji, bez współdzielonego mutowalnego dekodera.

Oczekiwanie na `URLSession` jest asynchronicznym I/O i nie wymaga przenoszenia na innego wykonawcę dla uniknięcia blokowania UI. Uzasadnieniem `@concurrent` jest synchroniczna praca przy dekodowaniu. Atrybut nie tworzy nowego zadania i zachowuje kontekst anulowania bieżącego zadania.

Nie dodajemy `Task.detached`, `TaskGroup`, GCD ani aktora do bezstanowej operacji tylko w celu demonstracji tych API.

## 7. API, model i błędy

Źródło: [TheMealDB API](https://www.themealdb.com/documentation).

Żądanie: `GET https://www.themealdb.com/api/json/v1/1/filter.php?c=Seafood`.

- `Meal`: identyfikator z `idMeal`, nazwa z `strMeal`, opcjonalny URL miniatury z `strMealThumb`.
- Stabilne ID pochodzi z API; nie generujemy UUID ani nie używamy indeksu jako tożsamości wiersza.
- Model może bezpośrednio implementować `Decodable` z `CodingKeys`; osobna kopia DTO nie jest potrzebna dla tych trzech pól.
- Obiekt odpowiedzi opakowujący `meals` pozostaje szczegółem klienta.
- `meals: []` i `meals: null` oznaczają pusty wynik.
- Brak wymaganego pola `meals`, niepoprawny JSON lub niezgodna struktura oznaczają błąd dekodowania.
- Klient sprawdza typ odpowiedzi i status HTTP przed dekodowaniem sukcesu; akceptuje statusy 2xx.
- `URLSession` jest wstrzykiwana do klienta, aby testy mogły używać własnej konfiguracji transportu.

Operacja klienta używa `async throws(MealAPIError)`. Enum rozróżnia transport, niepoprawną odpowiedź, status HTTP, dekodowanie i anulowanie. Zachowuje informacje potrzebne do diagnostyki, zamiast zastępować wszystkie przyczyny jednym ogólnym błędem.

`CancellationError`, anulowanie zadania oraz `URLError.cancelled` są obsługiwane spójnie. Przypadek anulowania nigdy nie staje się `MealsState.failed` ani błędem odświeżenia widocznym dla użytkownika.

## 8. SwiftUI i prezentacja

- Natywna `List` utrzymywana w stabilnej strukturze podczas aktualizacji danych.
- `.refreshable` dostępne również dla poprawnego pustego wyniku.
- `ProgressView` przy pierwszym ładowaniu.
- `ContentUnavailableView` dla błędu bez danych i pustego wyniku.
- Błąd odświeżenia pokazany przy zachowanej zawartości z przyciskiem ponowienia.
- `AsyncImage` z ustalonym rozmiarem miniatury, placeholderem oraz stanem niepowodzenia niezależnym od błędu listy.
- Obsługa Dynamic Type, VoiceOver oraz light/dark mode.
- Interfejs po angielsku.

Nie wymuszamy odtworzenia listy przez `.id(...)` podczas odświeżania. Dla tego samego zestawu elementów odświeżenie nie powinno resetować pozycji przewijania. Inicjalizacja widoków i obliczanie `body` nie wykonują operacji sieciowych.

## 9. Testy

### Unit testy klienta — Swift Testing

Wstrzyknięta `URLSession` z testowym `URLProtocol`, bez połączeń z publicznym API:

1. Poprawna metoda, ścieżka i parametr kategorii.
2. Dekodowanie reprezentatywnej odpowiedzi na modele wierszy.
3. Pusta tablica i `null` dają pusty wynik.
4. Brak pola `meals` oraz wadliwy JSON dają błąd dekodowania.
5. Status spoza 2xx daje błąd HTTP, nawet jeśli body nie jest JSON-em.
6. Błąd transportu zachowuje kategorię przyczyny.
7. Anulowanie zadania obejmuje operację prawdziwego klienta `URLSession` korzystającego z transportu testowego.

Stan transportu testowego jest synchronizowany i izolowany pomiędzy testami. Nie używamy niezabezpieczonego globalnego mutowalnego handlera ani wyłączeń kontroli concurrency dla uciszenia kompilatora.

### Unit testy ViewModelu — Swift Testing

Kontrolowany serwis umożliwia potwierdzenie rozpoczęcia żądania i jawne dostarczenie wyniku lub błędu. Testy nie bazują na arbitralnym `sleep` ani pętlach z `Task.yield()`.

1. Pierwsze pobranie: `idle → loading → loaded`.
2. Pusty wynik kończy się poprawnym `loaded([])`.
3. Błąd i skuteczne ponowienie.
4. Dane pozostają widoczne podczas odświeżania oraz po jego błędzie.
5. Sukces odświeżenia zastępuje dane i usuwa poprzedni błąd.
6. Nakładające się odświeżenie/ponowienie nie rozpoczyna drugiego requestu.
7. Anulowanie pierwszego pobrania przywraca `idle`; następna próba może się powieść.
8. Anulowanie odświeżenia zachowuje poprzednią kolekcję.
9. Sukces zwrócony mimo anulowania nie trafia do stanu.
10. Ponowne automatyczne wejście z załadowanymi danymi nie pobiera ponownie.
11. Nowe wejście podczas kończenia anulowanego pobierania ostatecznie rozpoczyna potrzebną próbę i nie pozostaje bezczynne w `idle`.

Każdy test kończy uruchomione zadania i rozwiązuje utworzone kontynuacje. Timeout testu jest ograniczeniem bezpieczeństwa, a nie mechanizmem sterowania kolejnością zdarzeń.

### UI i integracja lifecycle — XCTest

Scenariusze dostępne tylko w Debug, wybierane argumentami uruchomienia w punkcie składania zależności. Testy używają rzeczywistego ekranu i ViewModelu z podstawionym serwisem; nie ustawiają bezpośrednio stanu UI i nie omijają logiki aplikacji.

1. Uruchomienie pokazuje listę i pozwala ją przewinąć.
2. Pull-to-refresh dostarcza zmienioną zawartość i kończy wskaźnik odświeżania.
3. Błąd pierwszego pobrania, tapnięcie retry, następnie lista.
4. Pusty wynik i możliwość odświeżenia.

Osobny host testowy osadza rzeczywisty `MealsView` i pozwala go usunąć oraz ponownie osadzić z kontrolowanym serwisem. Weryfikuje:

- anulowanie pobierania po usunięciu widoku;
- anulowanie aktywnego pull-to-refresh;
- szybkie ponowne pojawienie się podczas kończenia anulowanej operacji;
- brak ponownego pobrania przy aktualizacji rodzica zachowującej tożsamość ekranu;
- brak zerwania pracy wskutek przejścia UI z `loading` do `loaded`.

Testy lifecycle mogą być hostowanymi testami integracyjnymi lub scenariuszami XCUITest — wybór zależy od możliwości wiarygodnego sterowania danym zdarzeniem. Muszą obejmować rzeczywisty cykl życia SwiftUI. Samo wywołanie metody anulowania nie zastępuje tej weryfikacji.

Obrazy w scenariuszach testowych nie zależą od zewnętrznej sieci. Testy czekają na konkretne obserwowalne warunki, nie na stałe opóźnienia.

## 10. Struktura plików i kolejność wykonania

Kod funkcji trafi do `DemoMealRecipes/Source/Features/Meals/`. Typy wspólnie opisujące jeden kontrakt mogą pozostać w jednym pliku. Testy klienta i ViewModelu trafią do istniejącego targetu unit testów, a scenariusze UI do istniejącego targetu UI testów.

1. Model `Meal`, kontrakt serwisu, klient i testy granicy HTTP.
2. Stan i ViewModel wraz z testami przejść, współbieżnych wywołań i anulowania.
3. Ekran oraz integracja pierwszego ładowania, retry i pull-to-refresh.
4. Testy lifecycle, szczególnie szybkie ponowne wejście i anulowanie odświeżenia.
5. Scenariusze UI oraz testy przepływów użytkownika.
6. Zastąpienie wejścia szablonu, usunięcie osieroconego sample feature i jego testów/zasobów, konfiguracja iPhone portrait.
7. README opisujący architekturę, wymagania toolchainu i scenariusze weryfikacji.
8. Build, testy i ręczne sprawdzenie rzeczywistego API.

Zmiany konfiguracji i usuwanie kodu ograniczają się do elementów potrzebnych dla tego zakresu. Istniejący krok formatowania podczas buildu należy uwzględnić przy kontroli końcowego diffu.

## 11. Dokumentacja edukacyjna

README wyjaśni na podstawie implementacji:

- dlaczego ViewModel jest obserwowalną klasą utrzymywaną w `@State`;
- różnicę pomiędzy odtworzeniem wartości widoku a zmianą jego tożsamości;
- gdzie powstają zadania i kto odpowiada za ich anulowanie;
- dlaczego bezpośrednie `await` i `Task {}` mają różne konsekwencje dla własności pracy;
- dlaczego `@MainActor` nie zapewnia atomowości całej operacji zawierającej `await`;
- różnicę między asynchronicznym I/O a dekodowaniem oraz rolę `@concurrent`;
- sposób zachowania danych po błędzie i anulowaniu;
- co potwierdzają testy jednostkowe, transportowe i lifecycle.

Kod pozostaje czytelny przez nazwy i strukturę. Wyjaśnienia decyzji trafiają do README. Komentarze w kodzie są ograniczone do nieoczywistych ograniczeń lub uzasadnionych obejść zachowania frameworka.

Źródła referencyjne:

- [Apple: Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- [Apple: View.task](https://developer.apple.com/documentation/swiftui/view/task(name:priority:file:line:_:))
- [Apple: View.refreshable](https://developer.apple.com/documentation/swiftui/view/refreshable(action:))
- [Swift Evolution: Structured concurrency — SE-0304](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md)
- [Swift Evolution: Async function isolation — SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md)

## 12. Kryteria ukończenia

- [x] Aplikacja uruchamia się na symulatorze iPhone'a z iOS 26+ w portrait.
- [x] Rzeczywiste API dostarcza przepisy widoczne na liście.
- [ ] Działają przewijanie, odświeżenie, pusty wynik, błąd i ponowienie.
- [ ] Odświeżenie zachowuje istniejącą zawartość i stabilną tożsamość wierszy.
- [ ] Jednocześnie nie powstają dwa żądania listy.
- [ ] Anulowanie nie publikuje błędu ani wyniku anulowanej operacji.
- [ ] Po anulowaniu i szybkim ponownym wejściu ekran może poprawnie pobrać dane.
- [ ] Integracja lifecycle jest potwierdzona testem hostowanego widoku lub UI.
- [ ] Przechodzą unit testy klienta i ViewModelu oraz UI testy.
- [ ] Build kończy się bez ostrzeżeń, w tym ostrzeżeń concurrency.
- [ ] Krótka ręczna kontrola obejmuje light/dark mode, większy Dynamic Type i podstawowe etykiety VoiceOver.
- [x] README odpowiada finalnej implementacji, w tym ewentualnym ograniczeniom potwierdzonym podczas testów.
- [ ] Końcowy diff zawiera wyłącznie zmiany związane z tym demo.

Pozycje bez zaznaczenia wymagają empirycznej weryfikacji (symulator, `make test`, ręczny przegląd UI). Kod funkcji, testy i README są na miejscu.
