#include <FastLED.h>

#define NUM_LEDS 24
#define DATA_PIN 10
#define BRIGHTNESS 128
#define SERIAL_BAUD 115200
#define LED_TYPE WS2812B
#define COLOR_ORDER GRB

CRGB leds[NUM_LEDS];

String currentState = "unknown";
String inputLine = "";

void showState(const String &state);
String normalizeState(String value);

void setup() {
  delay(100);

  Serial.begin(SERIAL_BAUD);

  FastLED.addLeds<LED_TYPE, DATA_PIN, COLOR_ORDER>(leds, NUM_LEDS);
  FastLED.setBrightness(BRIGHTNESS);
  FastLED.setMaxPowerInVoltsAndMilliamps(5, 1500);

  showState(currentState);
}

void loop() {
  while (Serial.available() > 0) {
    char ch = (char)Serial.read();

    if (ch == '\n') {
      String nextState = normalizeState(inputLine);
      inputLine = "";

      if (nextState != currentState) {
        currentState = nextState;
        showState(currentState);
      }
    } else if (ch != '\r') {
      inputLine += ch;

      if (inputLine.length() > 32) {
        inputLine = "";
      }
    }
  }
}

String normalizeState(String value) {
  value.trim();
  value.toLowerCase();

  if (value == "idle") {
    return "idle";
  }

  if (value == "working") {
    return "working";
  }

  if (value == "attention") {
    return "attention";
  }

  if (value == "unknown") {
    return "unknown";
  }

  return "unknown";
}

void showState(const String &state) {
  if (state == "idle") {
    fill_solid(leds, NUM_LEDS, CRGB::Green);
  } else if (state == "working") {
    fill_solid(leds, NUM_LEDS, CRGB::Yellow);
  } else if (state == "attention") {
    fill_solid(leds, NUM_LEDS, CRGB::Red);
  } else {
    fill_solid(leds, NUM_LEDS, CRGB::Blue);
  }

  FastLED.show();
}
