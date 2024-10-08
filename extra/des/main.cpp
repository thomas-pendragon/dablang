#include <algorithm>
#include <iostream>
#include <fstream>
#include <cmath>
#include <cstdlib>
#include <ctime>
#include <cassert>
#include <vector>
#include <thread>

#include <SFML/Window.hpp>
#include <SFML/Graphics.hpp>
#include <SFML/Audio.hpp>
#include <png.h>

// DES interface

void _des_callback_scanline(int sy);

struct des_palette
{
    uint8_t data[24];
};

void pack_uint4(uint8_t *data, uint16_t pos, uint8_t value)
{
    uint16_t big   = pos / 2;
    uint16_t small = pos % 2;
    uint8_t  shift = small ? 0 : 4;
    uint8_t  mask  = 0xF << (4 - shift);
    uint8_t *ptr   = data + big;
    *ptr &= mask;
    *ptr |= (value & 0xF) << shift;
}

uint8_t unpack_uint4(uint8_t *data, uint16_t pos)
{
    uint16_t big   = pos / 2;
    uint16_t small = pos % 2;
    uint8_t  shift = small ? 0 : 4;
    uint8_t *ptr   = data + big;
    return (*ptr >> shift) & 0xF;
}

struct des_tile
{
    uint8_t data[64];
};

struct TileData
{
    uint16_t tile;    // Tile index (10 bits)
    uint8_t  palette; // Palette index (4 bits)
    bool     vflip;   // Vertical flip flag (1 bit)
    bool     hflip;   // Horizontal flip flag (1 bit)
};

struct des_tilemap
{
    union
    {
        uint16_t data;
        uint8_t  bytes[2];
    };

    // uint16_t tile: 10;
    // uint16_t palette: 4;
    // uint16_t vflip: 1;
    // uint16_t hflip: 1;

    uint16_t tile() const
    {
        return bytes[0] << 2 | bytes[1] >> 6;
    }
    uint8_t palette() const
    {
        return (bytes[1] >> 2) & 0x0F;
    }

    uint8_t vflip() const
    {
        return (bytes[1] >> 1) & 0x01;
    }

    uint8_t hflip() const
    {
        return bytes[1] & 0x01;
    }

    des_tilemap()
    {
        data = 0;
    }
    des_tilemap(const TileData &tileData)
    {
        // Construct bytes from TileData
        bytes[0] = (tileData.tile & 0x3FF) >> 2; // Upper 8 bits of the tile
        bytes[1] = ((tileData.tile & 0x03) << 6) | ((tileData.palette & 0x0F) << 2) |
                   (tileData.vflip << 1) |
                   tileData.hflip; // Combine tile, palette, vflip, and hflip
    }
};

struct SpriteData
{
    uint8_t  x;           // X coordinate (8 bits)
    uint8_t  y;           // Y coordinate (8 bits)
    uint16_t tile;        // Tile index (10 bits)
    uint8_t  palette;     // Palette index (4 bits)
    bool     vflip;       // Vertical flip flag (1 bit)
    bool     hflip;       // Horizontal flip flag (1 bit)
    bool     enabled;     // Enabled flag (1 bit)
    bool     transparent; // Transparent flag (1 bit)

    // Constructor
    // SpriteData(uint8_t x, uint8_t y, uint16_t tile, uint8_t palette, bool vflip, bool hflip, bool
    // enabled, bool transparent)
    //        : x(x), y(y), tile(tile), palette(palette), vflip(vflip), hflip(hflip),
    //        enabled(enabled), transparent(transparent) {}
};

struct des_sprite
{
    uint8_t bytes[5];

    // XXXXXXXX
    // YYYYYYYY
    // TTTTTTTT
    // TTPPPPVH
    // ET000000

    // uint16_t x: 8;
    // uint16_t y: 8;
    // uint16_t tile: 10;
    // uint16_t palette: 4
    // uint16_t vflip: 1;
    // uint16_t hflip: 1;
    // uint16_t enabled: 1;
    // uint16_t transparent: 1;

    uint16_t x() const
    {
        return bytes[0];
    }

    uint16_t y() const
    {
        return bytes[1];
    }

    uint16_t tile() const
    {
        return ((bytes[2] & 0xFF) << 2) | (bytes[3] >> 6);
    }

    uint8_t palette() const
    {
        return (bytes[3] >> 2) & 0x0F;
    }

    uint8_t vflip() const
    {
        return (bytes[3] >> 1) & 0x01;
    }

    uint8_t hflip() const
    {
        return bytes[3] & 0x01;
    }

    uint8_t enabled() const
    {
        return (bytes[4] >> 7) & 0x01;
    }

    uint8_t transparent() const
    {
        return (bytes[4] >> 6) & 0x01;
    }

    des_sprite()
    {
        bytes[0] = 0;
        bytes[1] = 0;
        bytes[2] = 0;
        bytes[3] = 0;
        bytes[4] = 0;
    }
    des_sprite(const SpriteData &data)
    {
        bytes[0] = data.x;                   // Set x
        bytes[1] = data.y;                   // Set y
        bytes[2] = (data.tile & 0x3FF) >> 2; // Store the upper 8 bits of the 10-bit tile
        bytes[3] = ((data.tile & 0x03) << 6) | ((data.palette & 0x0F) << 2) | (data.vflip << 1) |
                   (data.hflip); // Combine tile, palette, vflip and hflip
        bytes[4] =
            (data.enabled << 7) | (data.transparent << 6); // Combine enabled and transparent flags
    }
};

struct des_bk
{
    uint16_t xOffset;
    uint16_t yOffset;
};

struct des_sound
{
    uint8_t note;     // 60 = middle C
    uint8_t velocity; // 4bit 0..15
    bool    enabled;
};

struct des_state
{
    des_palette palettes[16]     = {};
    des_tile    tiles[1024]      = {};
    des_tilemap tilemap[64 * 64] = {};
    des_sprite  sprites[40]      = {};
    des_bk      backgrounds[1]   = {};

    des_sound channels[1] = {};

    sf::Image screen;
} DES;

void des_sound_play(uint8_t channel, uint8_t note, uint8_t velocity)
{
    auto &ch    = DES.channels[channel];
    ch.enabled  = true;
    ch.note     = note;
    ch.velocity = velocity;
}

void des_sound_stop(uint8_t channel)
{
    DES.channels[channel].enabled = false;
}

int des_screen_width()
{
    return 256;
}
int des_screen_height()
{
    return 224;
}

// colors - RGB tuples, will be rounded down to 12 bit
void des_palette_copy(uint8_t paletteIndex, uint8_t colors[24])
{
    memcpy(&DES.palettes[paletteIndex], colors, 24);
}
// data - count * 64 bytes, each byte is color index, will be clamped to 16 colors/4 bit
void des_tileset_copy(uint16_t startIndex, uint16_t count, uint8_t *data)
{
    int size = std::min(count * 64, (1024 - startIndex) * 64);
    memcpy(&DES.tiles[startIndex], data, size);
}

void des_background_offset(uint8_t backgroundIndex, uint16_t xOffset, uint16_t yOffset)
{
    DES.backgrounds[backgroundIndex].xOffset = xOffset;
    DES.backgrounds[backgroundIndex].yOffset = yOffset;
}

// data:
// T - tile index, P - palette, VH - flip
// TTTTTTTT TTPPPPVH
void des_tilemap_copy(uint8_t startIndex, uint16_t count, uint8_t *data)
{
    memcpy(&DES.tilemap[startIndex], data, count * 2);
}

void des_sprite_enable(uint8_t index, const SpriteData *sd)
{
    auto copy          = *sd;
    copy.enabled       = true;
    DES.sprites[index] = des_sprite(copy);
}

void desx_load_png(const char *path, uint8_t paletteIndex = 0, uint16_t startIndex = 0)
{
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
    if (num_palette > 16)
    {
        fprintf(stderr, "[desx] error: palette must have at most 16 colors!\n");
        exit(1);
    }

    uint8_t des_palette[24];

    // Iterate over the palette and print out the RGB values
    for (int i = 0; i < num_palette; i++)
    {
        pack_uint4(des_palette, i * 3 + 0, palette[i].red >> 4);
        pack_uint4(des_palette, i * 3 + 1, palette[i].green >> 4);
        pack_uint4(des_palette, i * 3 + 2, palette[i].blue >> 4);
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
            uint8_t *des_palette = DES.palettes[y].data;

            auto i = x;

            auto r = unpack_uint4(des_palette, i * 3 + 0) << 4;
            auto g = unpack_uint4(des_palette, i * 3 + 1) << 4;
            auto b = unpack_uint4(des_palette, i * 3 + 2) << 4;

            sf::Color color(r, g, b);
            DES.screen.setPixel(x, y, color);
        }
    }
}

void _des_dump_tiles()
{
    static int z = 0;
    z++;
    int palI = (z / 60) % 4;
    //    palI=2;
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

                    int      i           = DES.tiles[tn].data[pp];
                    uint8_t *des_palette = DES.palettes[palI].data;

                    auto r = unpack_uint4(des_palette, i * 3 + 0) << 4;
                    auto g = unpack_uint4(des_palette, i * 3 + 1) << 4;
                    auto b = unpack_uint4(des_palette, i * 3 + 2) << 4;

                    sf::Color color(r, g, b);
                    DES.screen.setPixel(sx, sy, color);
                }
            }
        }
    }
}

void _des_render_tiles(int sy)
{
    const auto &bk = DES.backgrounds[0];

    //  for (int sy = 0; sy < 224; sy++)
    //    {
    for (int sx = 0; sx < 256; sx++)
    {
        uint16_t ssx = (sx + bk.xOffset) % 512;
        uint16_t ssy = (sy + bk.yOffset) % 512;

        int tile_x = ssx / 8;
        int tile_y = ssy / 8;
        int subx   = ssx % 8;
        int suby   = ssy % 8;
        int tile_n = tile_x + tile_y * 64;

        const auto &tile = DES.tilemap[tile_n];
        const auto  tId  = tile.tile();
        const auto  pId  = tile.palette();

        int pp = subx + suby * 8;

        int      i           = DES.tiles[tId].data[pp];
        uint8_t *des_palette = DES.palettes[pId].data;

        auto r = unpack_uint4(des_palette, i * 3 + 0) << 4;
        auto g = unpack_uint4(des_palette, i * 3 + 1) << 4;
        auto b = unpack_uint4(des_palette, i * 3 + 2) << 4;

        sf::Color color(r, g, b);
        DES.screen.setPixel(sx, sy, color);
    }
    // }
}

void _des_render_sprites(int sy)
{
    // for (int sy = 0; sy < 224; sy++)
    //    {
    for (int sx = 0; sx < 256; sx++)
    {
        for (int i = 0; i < 40; i++)
        {
            const auto &sp = DES.sprites[i];
            if (!sp.enabled())
                continue;
            int x = sp.x();
            int y = sp.y();

            x = sx - x;
            y = sy - y;

            if (x < 0 || x >= 8)
                continue;
            if (y < 0 || y >= 8)
                continue;

            const auto tId = sp.tile();
            const auto pId = sp.palette();

            int pp = x + y * 8;

            int ci = DES.tiles[tId].data[pp];

            auto ptra = ci == 0 && sp.transparent();

            if (ptra)
                continue;

            uint8_t *des_palette = DES.palettes[pId].data;

            auto r = unpack_uint4(des_palette, ci * 3 + 0) << 4;
            auto g = unpack_uint4(des_palette, ci * 3 + 1) << 4;
            auto b = unpack_uint4(des_palette, ci * 3 + 2) << 4;

            sf::Color color(r, g, b);
            DES.screen.setPixel(sx, sy, color);
        }
    }
    //   }
}

void _des_render()
{
    for (int sy = 0; sy < 224; sy++)
    {
        _des_callback_scanline(sy);
        _des_render_tiles(sy);
        _des_render_sprites(sy);
    }

    //  _des_dump_tiles();
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

void test()
{
    // void pack_uint4(uint8_t *data, uint16_t pos, uint8_t value)
    uint8_t data[2];

    pack_uint4(data, 0, 0xA);
    pack_uint4(data, 1, 0xB);
    pack_uint4(data, 2, 0xC);
    pack_uint4(data, 3, 0xD);

    fprintf(stderr, "%02X%02X\n", data[0], data[1]);

    assert(data[0] == 0xAB);
    assert(data[1] == 0xCD);

    assert(unpack_uint4(data, 0) == 0xA);
    assert(unpack_uint4(data, 1) == 0xB);
    assert(unpack_uint4(data, 2) == 0xC);
    assert(unpack_uint4(data, 3) == 0xD);
}
int frameCounter = 0;

void des_tilemap_set(int tileX, int tileY, int tile, int palette, bool vflip, bool hflip)
{
    TileData td;
    td.tile        = tile;
    td.palette     = palette;
    td.vflip       = vflip;
    td.hflip       = hflip;
    int n          = tileX + tileY * 32;
    DES.tilemap[n] = td;
}

void desx_text_print(int tileX, int tileY, const char *str, int letterOffset, int palette)
{
    static bool ok  = true;
    int         len = strlen(str);
    for (int i = 0; i < len; i++)
    {
        int ch = toupper(str[i]) - 'A' + 34 - 1;
        if (ok)
            fprintf(stderr, "print(%d '%c') -> %d (%d)\n", i, str[i], ch, letterOffset + ch);
        des_tilemap_set(tileX + i, tileY, letterOffset + ch, palette, false, false);
    }
    ok = false;
}

void _des_callback_scanline(int sy)
{
    des_background_offset(
        0, sy > 8 ? frameCounter + sin(2.5 * frameCounter * 0.1 + 3.1415 * 2 * sy / 244.0) * 4 : 0,
        0);
    // des_background_offset(0, sy > 8 ? frameCounter : 0, 0);
}
void _des_callback_frame()
{
    char buffer[128];
    snprintf(buffer, 128, "Frame %d!", frameCounter);
    desx_text_print(0, 0, buffer, 256, 1);
    //    static int allC = 0;
    frameCounter++;
    static int c = 0;
    c++;
    static int st = 0;
    if (c == 10)
    {
        st++;
        st = st % 4;
        c  = 0;
    }

    // des_background_offset(0, allC, 0);

    int pp = 2;
    int bT = 320; // 168

    int sta = st;
    if (sta == 3)
        sta = 1;

    // bT += 12;
    bT += sta * 2;

    int        bX  = 41;
    int        bY  = 23;
    SpriteData sp  = {};
    sp.x           = bX;
    sp.y           = bY;
    sp.tile        = bT;
    sp.palette     = pp;
    sp.transparent = true;
    des_sprite_enable(0, &sp);
    // SpriteData sp = {};
    sp.x    = bX + 8;
    sp.y    = bY;
    sp.tile = bT + 1;
    // sp.palette = pp;
    des_sprite_enable(1, &sp);
    // SpriteData sp = {};
    sp.x    = bX;
    sp.y    = bY + 8;
    sp.tile = bT + 6;
    // sp.palette = pp;
    des_sprite_enable(2, &sp);
    // SpriteData sp = {};
    sp.x    = bX + 8;
    sp.y    = bY + 8;
    sp.tile = bT + 6 + 1;
    // sp.palette = pp;
    des_sprite_enable(3, &sp);
}

float sqwave(double x)
{
    // return std::sin(x);
    return 2 * (fmod(x, 2 * M_PI) >= M_PI) - 1;
}

template <typename T>
class LockFreeByteQueue //<T>
{
  public:
    LockFreeByteQueue(size_t bufferSize, size_t chunkSize)
        : buffer(bufferSize * sizeof(T)), chunkSize(chunkSize * sizeof(T)), head(0), tail(0)
    {
    }

    bool enqueue(const T *data)
    {
        size_t current_tail = tail.load(std::memory_order_relaxed);
        size_t next_tail    = (current_tail + chunkSize) % buffer.size();

        // Check if the queue has enough space for the chunk
        if (next_tail == head.load(std::memory_order_acquire))
        {
            return false; // Queue is full
        }

        // Copy N bytes (chunkSize) from the data into the buffer
        std::memcpy(&buffer[current_tail], data, chunkSize);
        tail.store(next_tail, std::memory_order_release);
        return true;
    }

    bool dequeue(T *data)
    {
        size_t current_head = head.load(std::memory_order_relaxed);

        // Check if the queue is empty
        if (current_head == tail.load(std::memory_order_acquire))
        {
            return false; // Queue is empty
        }

        // Copy N bytes (chunkSize) from the buffer into the output data
        std::memcpy(data, &buffer[current_head], chunkSize);
        head.store((current_head + chunkSize) % buffer.size(), std::memory_order_release);
        return true;
    }

  private:
    std::vector<char>   buffer;    // Byte buffer
    size_t              chunkSize; // Number of bytes per operation
    std::atomic<size_t> head, tail;
};

constexpr const int CLOCK_INTERVAL = 1000;

constexpr const unsigned int SAMPLE_RATE       = 44100;   // 44.1 kHz
constexpr const unsigned int SAMPLES_PER_CHUNK = 2 * 512; // 2048;
constexpr const float        MIDDLE_C          = 261.625565;

constexpr int ceil_div(int x, int y)
{
    return (x + y - 1) / y;
}

constexpr const size_t SAMPLES_PER_GEN =
    ceil_div(SAMPLE_RATE, CLOCK_INTERVAL); // Number of bytes per chunk
constexpr const size_t NUMBER_OF_GENS   = ceil_div(SAMPLES_PER_CHUNK, SAMPLES_PER_GEN);
constexpr const size_t REAL_BUFFER_SIZE = NUMBER_OF_GENS * SAMPLES_PER_GEN;

LockFreeByteQueue<short> queue(REAL_BUFFER_SIZE * 4, SAMPLES_PER_GEN);

int soundPosition = 0;

void genMoreSoundData()
{
    static int   geni = 0;
    static short samples[SAMPLES_PER_GEN];
    const auto  &snd = DES.channels[0];

    for (unsigned int i = 0; i < SAMPLES_PER_GEN; ++i)
    {
        float freq   = MIDDLE_C * pow(2.0, (snd.note - 60.0) / 12.0);
        float sample = (32767 - 1) * ((float)snd.velocity / 15.0) * (snd.enabled ? 1 : 0) *
                       sqwave(2 * 3.14159f * freq * (soundPosition + i) / SAMPLE_RATE);
        samples[i] = sample;
    }
    soundPosition += SAMPLES_PER_GEN;

    int i = 0;
    while (true)
    {
        if (queue.enqueue(samples))
            break;
        i++;
        sf::sleep(sf::Time::Zero);
    }
    // if(i>0)    fprintf(stderr, "%8d: sound queued after %d tries\n",geni,i);
    geni++;
}

class CustomStream : public sf::SoundStream
{
    short samples[REAL_BUFFER_SIZE];

  public:
    bool open(const std::string &location)
    {
        // Open the source and get audio settings
        //...
        unsigned int channelCount = 1;           //...;
        unsigned int sampleRate   = SAMPLE_RATE; //...;

        fprintf(stderr,
                "init sound engine with play chunks of %d samples (target was %d), gen chunks of "
                "%d samples and %d gen buffer of %d samples total\n",
                (int)REAL_BUFFER_SIZE, (int)SAMPLES_PER_CHUNK, (int)SAMPLES_PER_GEN,
                (int)NUMBER_OF_GENS, (int)REAL_BUFFER_SIZE * 4);

        // Initialize the stream -- important!
        initialize(channelCount, sampleRate);
        return true;
    }

  private:
    int          pos = 0;
    virtual bool onGetData(Chunk &data)
    {
        for (int i = 0; i < NUMBER_OF_GENS; i++)
        {

            while (true)
            {
                if (queue.dequeue(&samples[SAMPLES_PER_GEN * i]))
                {
                    break;
                }
                fprintf(stderr, "sound queue %d empty, wait...\n", i);
            }
        }
        //        fprintf(stderr,"> sound ate %d bytes in
        //        total\n",(int)(SAMPLES_PER_GEN*NUMBER_OF_GENS));

        // Fill the chunk with audio data from the stream source
        // (note: must not be empty if you want to continue playing)
        data.samples     = samples;          //...;
        data.sampleCount = REAL_BUFFER_SIZE; //...;

        // Return true to continue playing
        return true;
    }

    virtual void onSeek(sf::Time timeOffset)
    {
        // Change the current position in the stream source
        //...
    }
};

struct Note
{
    int   note;
    float length;
    float amplitude;
};

Note notes[] = {

    {71, 0.2, 1},     {69, 0.2, 1},     {68, 0.2, 1},     {69, 0.2, 1},     {72, 0.2, 1},
    {0, 0.6, 0},

    {71 + 3, 0.2, 1}, {69 + 3, 0.2, 1}, {68 + 3, 0.2, 1}, {69 + 3, 0.2, 1}, {72 + 3 + 1, 0.2, 1},
    {0, 0.6, 0},

    {77, 0.2, 1},     {76, 0.2, 1},     {75, 0.2, 1},     {76, 0.2, 1},

    {83, 0.2, 1},     {81, 0.2, 1},     {80, 0.2, 1},     {81, 0.2, 1},

    {83, 0.2, 1},     {81, 0.2, 1},     {80, 0.2, 1},     {81, 0.2, 1},

    {84, 0.2, 1},     {0, 0.6, 0},

    {81, 0.2, 1},     {0, 0.2, 0},      {84, 0.2, 1},     {0, 0.2, 0},

    {79, 0.067, 1},   {81, 0.067, 1},   {83, 0.067, 1},

    {0, 0.2, 0},      {81, 0.2, 1},     {0, 0.2, 0},      {79, 0.2, 1},     {0, 0.2, 0},
    {81, 0.2, 1},     {0, 0.2, 0},

    {79, 0.067, 1},   {81, 0.067, 1},   {83, 0.067, 1},

    {0, 0.2, 0},      {81, 0.2, 1},     {0, 0.2, 0},      {79, 0.2, 1},     {0, 0.2, 0},
    {81, 0.2, 1},     {0, 0.2, 0},

    {79, 0.067, 1},   {81, 0.067, 1},   {83, 0.067, 1},

    {0, 0.2, 0},      {81, 0.2, 1},     {0, 0.2, 0},      {79, 0.2, 1},     {0, 0.2, 0},
    {78, 0.2, 1},     {0, 0.2, 0},      {76, 0.2, 1},     {0, 0.6, 0},

    {-1, 0, 0}};

struct MusicPlayback
{
    Note *notes;
    float p = 0;
    MusicPlayback(Note *notes)
    {
        this->notes = notes;
    }
    float length()
    {
        float res   = 0.0;
        auto  cNote = notes;
        while (true)
        {
            auto note = *cNote;
            if (note.note == -1)
                break;
            res += note.length;
            cNote++;
        }
        return res;
    }
    void update(float dt)
    {
        dt *= 2.0; // 0.25;
        p += dt;
        static int cc = 0;
        cc++;

        auto t     = p;
        auto cNote = notes;
        int  i     = 0;
        while (true)
        {
            auto note = *cNote;
            // fprintf(stderr,"%d: %f (%f): %f: check %d
            // %f\n",cc,p,length(),t,note.note,note.length);
            cc++;
            // if(cc>100)exit(9);
            if (note.note == -1)
            {
                cNote = notes;
                p -= length();
                t = p;
                continue;
            }
            if (note.length > t)
            {
                if (DES.channels[0].note != note.note)
                    fprintf(stderr, "%f: play note %d for %f\n", p, note.note, note.length);
                des_sound_play(0, note.note, note.amplitude * 15 * 0.1);
                break;
            }
            t -= note.length;
            cNote++;
            i++;
        }
    }
};

MusicPlayback mp(notes);
void          _des_callback_time(uint16_t sec, uint16_t mili)
{
    //    static
    mp.update(1.0 / 1000.0);
    // if (mili==0) fprintf(stderr,"TIME %d %d\n", sec, mili);
}

void clockTask()
{
    sf::Clock clock;
    float     t        = 0.0;
    float     interval = 1.0 / 1000.0; // 00.0;

    uint16_t sec  = 0;
    uint16_t mili = 0;

    while (true)
    {
        float t2 = clock.getElapsedTime().asSeconds();
        float dt = t2 - t;
        while (dt > interval)
        {
            mili++;
            if (mili == 1000)
            {
                mili = 0;
                sec++;
            }
            _des_callback_time(sec, mili);
            genMoreSoundData();
            dt -= interval;
            t += interval;
        }
    }
}

enum
{
    DES_KEY_UP     = 1,
    DES_KEY_DOWN   = 2,
    DES_KEY_LEFT   = 3,
    DES_KEY_RIGHT  = 4,
    DES_KEY_A      = 5,
    DES_KEY_B      = 6,
    DES_KEY_START  = 7,
    DES_KEY_SELECT = 8
};

int sf_key_to_des(sf::Keyboard::Key key)
{
    if (key == sf::Keyboard::X)
        return DES_KEY_A;
    if (key == sf::Keyboard::Z)
        return DES_KEY_B;
    if (key == sf::Keyboard::Space)
        return DES_KEY_SELECT;
    if (key == sf::Keyboard::Enter)
        return DES_KEY_START;
    if (key == sf::Keyboard::Left)
        return DES_KEY_LEFT;
    if (key == sf::Keyboard::Right)
        return DES_KEY_RIGHT;
    if (key == sf::Keyboard::Up)
        return DES_KEY_UP;
    if (key == sf::Keyboard::Down)
        return DES_KEY_DOWN;
    return 0;
}

void _des_callback_key(uint8_t key, bool down)
{
    fprintf(stderr, "key %d %s\n", key, down ? "down" : "up");
}

int main()
{
    //    test();
    //    std::thread audioThread(audioTask);

    std::thread clockThread(clockTask);

    CustomStream stream;
    stream.open("path/to/stream");
    stream.play();

    //   audio();

    // Set the size of the window to 256x224
    const int scale        = 3;
    int       w            = des_screen_width();
    int       h            = des_screen_height();
    const int windowWidth  = w * scale;
    const int windowHeight = h * scale;

    // Create the window
    sf::RenderWindow window(sf::VideoMode(windowWidth, windowHeight), "DES");
    window.setFramerateLimit(60);
    window.setKeyRepeatEnabled(false);

    DES.screen.create(des_screen_width(), des_screen_height());

    sf::Texture texture;
    texture.create(des_screen_width(), des_screen_height());

    // Create a sprite to display the texture
    sf::Sprite sprite;
    sprite.setScale(static_cast<float>(scale),
                    static_cast<float>(scale)); // Scale sprite to window size

    // CC-BY 3.0 https://opengameart.org/content/tileset-1bit-color
    desx_load_png("tileset_1bit.png", 0, 0); // 256);

    // CC0 https://opengameart.org/content/8x8-1bit-roguelike-tiles-bitmap-font
    desx_load_png("glyphs_mini.png", 1, 256);

    // CC-BY-SA 3.0 https://route1rodent.itch.io/16x16-rpg-character-sprite-sheet
    desx_load_png("player.png", 2, 320);

    // Credit goes to Daniel Cook's 2d Circle Graphic Archive, Jetrel's mockups resized 32x32,
    // Bertram's improvements, Zabin's modification and additions, Saphy (TMW) tall grass and please
    // provide a link back to OGA and this submission.
    // https://opengameart.org/content/2d-lost-garden-zelda-style-tiles-resized-to-32x32-with-additions
    // desx_load_png("mountain_landscape_16c_256.png", 3, 320 + 12 * 4);

    uint16_t tilemap[64 * 64];
    FILE    *f = fopen("rpg1.dat", "rb");
    fread(tilemap, 2, 64 * 64, f);
    fclose(f);

    des_tilemap_copy(0, 64 * 64, (uint8_t *)tilemap);

    bool tiles = false;

    FPSChecker fpsChecker;
    while (window.isOpen())
    {
        fpsChecker.ping(window);
        sf::Event event;
        while (window.pollEvent(event))
        {
            if (event.type == sf::Event::Closed)
            {
                window.close();
                exit(0);
            }

            if (event.type == sf::Event::KeyReleased || event.type == sf::Event::KeyPressed)
            {
                auto key = sf_key_to_des(event.key.code);
                if (key)
                {
                    _des_callback_key(key, event.type == sf::Event::KeyPressed);
                }
            }

            if (event.type == sf::Event::KeyPressed)
            {
                if (event.key.code == sf::Keyboard::T) // Check if the "T" key was pressed
                {
                    tiles ^= true;
                }
            }
        }

        _des_callback_frame();
        _des_render();
        char fn[128];
        snprintf(fn, 128, "frames/%05d.png", frameCounter);
        // DES.screen.saveToFile(fn);//"filename.png")
        if (tiles)
            _des_dump_tiles();

        texture.update(DES.screen);
        sprite.setTexture(texture);
        window.draw(sprite);
        window.display();
    }

    return 0;
}
