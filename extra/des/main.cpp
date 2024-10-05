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
#include <algorithm>

// DES interface

struct des_palette
{
    uint8_t data[16 * 3];
};

struct des_tile
{
    uint8_t data[64];
};

struct des_state
{
    des_palette palettes[16];
    des_tile    tiles[1024];

    sf::Image screen;
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
void des_tileset_copy(uint16_t startIndex, uint16_t count, uint8_t *data)
{
    int size = std::min(count * 64, (1024 - startIndex) * 64);
    memcpy(&DES.tiles[startIndex], data, size);
}

// data:
// T - tile index, P - palette, VH - flip
// TTTTTTTT TTPPPPVH
int des_tilemap_copy(uint8_t startIndex, uint8_t *data);

void desx_load_png(const char *path, uint8_t paletteIndex = 0, uint16_t startIndex = 0)
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

    if (width % 8 || height % 8)
    {
        fprintf(stderr, "[desx] error: width and height must be divible by 8\n");
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
        des_palette[i * 3 + 0] = palette[i].red >> 4 << 4;
        des_palette[i * 3 + 1] = palette[i].green >> 4 << 4;
        des_palette[i * 3 + 2] = palette[i].blue >> 4 << 4;
        fprintf(stderr, "Color %d: R=%d, G=%d, B=%d -> %d %d %d\n", i, palette[i].red,
                palette[i].green, palette[i].blue, des_palette[i * 3 + 0], des_palette[i * 3 + 1],
                des_palette[i * 3 + 2]);
    }

    des_palette_copy(paletteIndex, des_palette);

    // Allocate memory for reading the indexed pixel data
    png_bytep *row_pointers = (png_bytep *)malloc(sizeof(png_bytep) * height);
    size_t     rowsize      = png_get_rowbytes(png, info);
    png_byte  *rowdata      = (png_byte *)malloc(rowsize * height);
    for (int y = 0; y < height; y++)
    {
        row_pointers[y] = rowdata + rowsize * y;
    }

    // Read the image data (pixel indices)
    png_read_image(png, row_pointers);

    int x_tiles = width / 8;
    int y_tiles = height / 8;

    int n_tiles = x_tiles * y_tiles;

    uint8_t *tileData = new uint8_t[n_tiles * 64];

    int nq = 0;

    for (int yt = 0; yt < y_tiles; yt++)
    {
        for (int xt = 0; xt < x_tiles; xt++)
        {
            int      tileIndex = xt + yt * x_tiles;
            uint8_t *ptr       = &tileData[tileIndex * 64];

            for (int y = 0; y < 8; y++)
            {
                for (int x = 0; x < 8; x++)
                {
                    int xx = xt * 8 + x;
                    int yy = yt * 8 + y;

                    ptr[x + y * 8] = row_pointers[yy][xx];
                    nq++;
                }
            }
        }
    }
    des_tileset_copy(startIndex, n_tiles, tileData);
    delete[] tileData;

    free(rowdata);
    free(row_pointers);

    png_destroy_read_struct(&png, &info, NULL);
    fclose(fp);
}

void _des_dump_palettes()
{
    for (int y = 0; y < 16; y++)
    {
        for (int x = 0; x < 16; x++)
        {
            uint8_t  *cc = &DES.palettes[y].data[x * 3];
            sf::Color color(*(cc + 0), *(cc + 1), *(cc + 2));
            DES.screen.setPixel(x, y, color);
        }
    }
}

void _des_render()
{
    for (int ty = 0; ty < 28; ty++)
    {
        for (int tx = 0; tx < 32; tx++)
        {
            int tn = tx + ty * 32;

            for (int y = 0; y < 8; y++)
            {
                for (int x = 0; x < 8; x++)
                {

                    int sx = x + tx * 8;
                    int sy = y + ty * 8;

                    int pp = x + y * 8;

                    int      pIndex = DES.tiles[tn].data[pp];
                    uint8_t *cc     = &DES.palettes[0].data[pIndex * 3];

                    sf::Color color(*(cc + 0), *(cc + 1), *(cc + 2));
                    DES.screen.setPixel(sx, sy, color);
                }
            }
        }
    }
}

struct FPSChecker
{
    sf::Clock clock;
    float     t        = 0;
    int       counter  = 0;
    int       interval = 60;

    void ping(sf::RenderWindow &window)
    {
        counter++;
        if (counter == interval)
        {
            float t2 = clock.getElapsedTime().asSeconds();
            float dt = t2 - t;
            t        = t2;
            counter  = 0;
            char buffer[256];
            snprintf(buffer, 256, "DES :: fps = %f", (float)interval / dt);
            window.setTitle(buffer);
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

    DES.screen.create(des_screen_width(), des_screen_height());

    sf::Texture texture;
    texture.create(des_screen_width(), des_screen_height());

    // Create a sprite to display the texture
    sf::Sprite sprite;
    sprite.setScale(static_cast<float>(scale),
                    static_cast<float>(scale)); // Scale sprite to window size

    // CC0 https://opengameart.org/content/8x8-1bit-roguelike-tiles-bitmap-font
    desx_load_png("glyphs.png", 1, 0);

    // Credit goes to Daniel Cook's 2d Circle Graphic Archive, Jetrel's mockups resized 32x32,
    // Bertram's improvements, Zabin's modification and additions, Saphy (TMW) tall grass and please
    // provide a link back to OGA and this submission.
    // https://opengameart.org/content/2d-lost-garden-zelda-style-tiles-resized-to-32x32-with-additions
    desx_load_png("mountain_landscape_16c_256.png", 0, 256);

    FPSChecker fpsChecker;
    while (window.isOpen())
    {
        fpsChecker.ping(window);
        sf::Event event;
        while (window.pollEvent(event))
        {
            if (event.type == sf::Event::Closed)
                window.close();
        }

        _des_render();
        texture.update(DES.screen);
        sprite.setTexture(texture);
        // window.clear();
        window.draw(sprite);
        window.display();
    }

    return 0;
}
