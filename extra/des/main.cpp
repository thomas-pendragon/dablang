#include <GL/glew.h>  // Include GLEW first

#include <SFML/Window.hpp>
#include <SFML/OpenGL.hpp>

#include <iostream>
#include <fstream>
#include <glm/glm.hpp>   // For GLM matrices
#include <glm/gtc/matrix_transform.hpp>
#include <cmath>

#include <SFML/Graphics.hpp>
#include <cstdlib>
#include <ctime>

// DES interface

// colors - RGB tuples, will be rounded down to 12 bit
void des_palette_setup(uint8_t paletteIndex, uint8_t colors[16 * 3]);
// data - count * 64 bytes, each byte is color index, will be clamped to 16 colors/4 bit
void des_tileset_copy(uint8_t startIndex, uint8_t count, uint8_t *data);






int main() {
    // Set the size of the window to 256x224
    const int scale = 3;
    int w = 256;
    int h = 224;
    const int windowWidth = w * scale;
    const int windowHeight = h * scale;
    const int rectSize = scale;  // Each rectangle will be 2x2

    // Create the window
    sf::RenderWindow window(sf::VideoMode(windowWidth, windowHeight), "Random Pixels");
    window.setFramerateLimit(60);

    // Seed the random number generator
    std::srand(static_cast<unsigned int>(std::time(nullptr)));

    sf::Clock clock;
    float t = 0;

    // Run the program as long as the window is open
    while (window.isOpen()) {
        // Check all the window's events

        float t2 = static_cast<float>(clock.getElapsedTime().asSeconds());
        float dt = t2 - t;
        t = t2;
        fprintf(stderr, "t = %f, fps = %f\n", dt, 1.0 / dt);

        sf::Event event;
        while (window.pollEvent(event)) {
            if (event.type == sf::Event::Closed)
                window.close();
        }

        // Clear the window
        window.clear();

        // Draw random 2x2 rectangles
        for (int y = 0; y < h; y += 1) {
            for (int x = 0; x < w; x += 1) {
                // Create a 2x2 rectangle
                sf::RectangleShape rect(sf::Vector2f(rectSize, rectSize));

                // Set random color for the rectangle
                rect.setFillColor(sf::Color(
                    std::rand() % 256,   // Red
                    std::rand() % 256,   // Green
                    std::rand() % 256    // Blue
                ));

                // Set position for the rectangle
                rect.setPosition(static_cast<float>(x * scale), static_cast<float>(y * scale));

                // Draw the rectangle
                window.draw(rect);
            }
        }

        // Display what has been drawn to the window
        window.display();
    }

    return 0;
}
