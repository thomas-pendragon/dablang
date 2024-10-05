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

    // Create the window
    sf::RenderWindow window(sf::VideoMode(windowWidth, windowHeight), "Random Pixels with Texture");
    window.setFramerateLimit(60);

    // Seed the random number generator
    std::srand(static_cast<unsigned int>(std::time(nullptr)));

    sf::Clock clock;
    float t = 0;

    // Create an image with the size of the screen (256x224)
    sf::Image image;
    image.create(w, h);

    // Create a texture to load the image
    sf::Texture texture;
    texture.create(w, h);

    // Create a sprite to display the texture
    sf::Sprite sprite;
    sprite.setScale(static_cast<float>(scale), static_cast<float>(scale)); // Scale sprite to window size

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

        // Set random pixels in the image
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                // Generate random color for each pixel
                sf::Color color(
                    std::rand() % 256,  // Red
                    std::rand() % 256,  // Green
                    std::rand() % 256   // Blue
                );
                image.setPixel(x, y, color);
            }
        }

        // Update the texture with the modified image
        texture.update(image);

        // Set the texture to the sprite
        sprite.setTexture(texture);

        // Clear the window
        window.clear();

        // Draw the sprite (which contains the updated texture)
        window.draw(sprite);

        // Display what has been drawn to the window
        window.display();
    }

    return 0;
}
