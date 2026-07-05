#include <FastLED.h>

#define NUM_LEDS 24
#define DATA_PIN 10
#define BRIGHTNESS 128
#define LED_TYPE WS2812B
#define COLOR_ORDER GRB

CRGB leds[NUM_LEDS];
uint8_t hue = 0;

void setup() {
  delay(100);

  FastLED.addLeds<LED_TYPE, DATA_PIN, COLOR_ORDER>(leds, NUM_LEDS);
  FastLED.setBrightness(BRIGHTNESS);
  FastLED.setMaxPowerInVoltsAndMilliamps(5, 1500);
}

void loop() {
  fill_rainbow(leds, NUM_LEDS, hue, 8);
  FastLED.show();

  hue++;
  delay(20);
}
