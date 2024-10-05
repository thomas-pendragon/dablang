#include <GL/glew.h> // Include GLEW first

#include <SFML/Window.hpp>
#include <SFML/OpenGL.hpp>

#include <iostream>
#include <fstream>
#include <glm/glm.hpp> // For GLM matrices
#include <glm/gtc/matrix_transform.hpp>
#include <cmath>

#include <SFML/Graphics.hpp>
#include <cstdlib>
#include <ctime>

#include <png.h>
#include <zlib.h>

// DES interface

sf::Image image;

struct des_palette
{
    uint8_t data[16 * 3];
};

struct des_state
{
    des_palette palettes[16];
} DES;

int des_screen_width()
{
    return 256;
}
int des_screen_height()
{
    return 224;
}

// colors - RGB tuples, will be rounded down to 12 bit
void des_palette_copy(uint8_t paletteIndex, uint8_t colors[16 * 3])
{
    memcpy(&DES.palettes[paletteIndex], colors, 16 * 3);
}
// data - count * 64 bytes, each byte is color index, will be clamped to 16 colors/4 bit
void des_tileset_copy(uint8_t startIndex, uint8_t count, uint8_t *data);

// data:
// T - tile index, P - palette, VH - flip
// TTTTTTTT TTPPPPVH
int des_tilemap_copy(uint8_t startIndex, uint8_t *data);

void desx_load_png(const char *path)
{
    // sf::Image image;
    // if (!image.loadFromFile(path)) {
    //   throw "fail";
    //   }
    //   fprintf(stderr,"loaded %d x %d\n", image.width(), image.height());
    png_structp png  = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    png_infop   info = png_create_info_struct(png);
    FILE       *fp   = fopen(path, "rb");
    png_init_io(png, fp);
    png_read_info(png, info);
    png_uint_32 width      = png_get_image_width(png, info);
    png_uint_32 height     = png_get_image_height(png, info);
    int         color_type = png_get_color_type(png, info);
    int         bit_depth  = png_get_bit_depth(png, info);

    fprintf(stderr,
            "[desx] Loaded '%s': %dx%d pixels, %d color type (PNG_COLOR_TYPE_PALETTE = %d), %d bit "
            "depth\n",
            path, (int)width, (int)height, color_type, (int)PNG_COLOR_TYPE_PALETTE, bit_depth);

    if (color_type != PNG_COLOR_TYPE_PALETTE)
    {
        fprintf(stderr, "[desx] error: must be indexed png\n");
        exit(1);
    }

    png_colorp palette;
    int        num_palette;

    if (png_get_PLTE(png, info, &palette, &num_palette) != PNG_INFO_PLTE)
    {
        fprintf(stderr, "[desx] error: no palette\n");
        exit(1);
    }

    fprintf(stderr, "[desx] palette has %d colors\n", num_palette);
    if (num_palette != 16)
    {
        fprintf(stderr, "[desx] error: palette must have 16 colors!\n");
        exit(1);
    }

    uint8_t des_palette[16 * 3];

    // Iterate over the palette and print out the RGB values
    for (int i = 0; i < num_palette; i++)
    {
        des_palette[i * 3 + 0] = palette[i].red;
        des_palette[i * 3 + 1] = palette[i].green;
        des_palette[i * 3 + 2] = palette[i].blue;
        fprintf(stderr, "Color %d: R=%d, G=%d, B=%d\n", i, palette[i].red, palette[i].green,
                palette[i].blue);
    }

    des_palette_copy(0, des_palette);

    png_destroy_read_struct(&png, &info, NULL);
    fclose(fp);
}

void _des_render()
{
    // Dump palette
    for (int y = 0; y < 16; y++)
    {
        for (int x = 0; x < 16; x++)
        {
            // Generate random color for each pixel
            uint8_t  *cc = &DES.palettes[y].data[x * 3];
            sf::Color color(*(cc + 0), *(cc + 1), *(cc + 2));
            image.setPixel(x, y, color);
        }
    }
}

struct FPSChecker
{
    sf::Clock clock;
    float     t        = 0;
    int       counter  = 0;
    int       interval = 60;

    void ping()
    {
        counter++;
        if (counter == interval)
        {
            float t2 = clock.getElapsedTime().asSeconds();
            float dt = t2 - t;
            t        = t2;
            counter  = 0;
            fprintf(stderr, "t = %f, fps = %f\n", dt, (float)interval / dt);
        }
    }
};

int main()
{
    // Set the size of the window to 256x224
    const int scale        = 3;
    int       w            = des_screen_width();
    int       h            = des_screen_height();
    const int windowWidth  = w * scale;
    const int windowHeight = h * scale;

    // Create the window
    sf::RenderWindow window(sf::VideoMode(windowWidth, windowHeight), "Random Pixels with Texture");
    window.setFramerateLimit(60);

    image.create(des_screen_width(), des_screen_height());

    sf::Texture texture;
    texture.create(des_screen_width(), des_screen_height());

    // Create a sprite to display the texture
    sf::Sprite sprite;
    sprite.setScale(static_cast<float>(scale),
                    static_cast<float>(scale)); // Scale sprite to window size

    // Credit goes to Daniel Cook's 2d Circle Graphic Archive, Jetrel's mockups resized 32x32,
    // Bertram's improvements, Zabin's modification and additions, Saphy (TMW) tall grass and please
    // provide a link back to OGA and this submission.
    // https://opengameart.org/content/2d-lost-garden-zelda-style-tiles-resized-to-32x32-with-additions
    desx_load_png("mountain_landscape_16c_256.png");

    FPSChecker fpsChecker;
    while (window.isOpen())
    {
        fpsChecker.ping();
        sf::Event event;
        while (window.pollEvent(event))
        {
            if (event.type == sf::Event::Closed)
                window.close();
        }

        _des_render();
        texture.update(image);
        sprite.setTexture(texture);
        // window.clear();
        window.draw(sprite);
        window.display();
    }

    return 0;
}
