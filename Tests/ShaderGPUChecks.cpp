// Execute the actual bundled SkSL on Skia's GPU backend; no CPU fallback.
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl3.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include "include/c/gr_context.h"
#include "include/c/sk_canvas.h"
#include "include/c/sk_data.h"
#include "include/c/sk_image.h"
#include "include/c/sk_paint.h"
#include "include/c/sk_runtimeeffect.h"
#include "include/c/sk_shader.h"
#include "include/c/sk_string.h"
#include "include/c/sk_surface.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>

using Pixels = std::vector<unsigned char>;
static void require(bool value, const std::string& message) {
    if (!value) throw std::runtime_error(message);
}

struct Program {
    sk_runtimeeffect_t* effect;
    size_t offsets[12];
    explicit Program(const char* path) {
        std::ifstream file(path);
        require(file.good(), "Cannot read the actual SkSL resource");
        std::string source((std::istreambuf_iterator<char>(file)), {});
        auto* text = sk_string_new_with_copy(source.data(), source.size());
        auto* error = sk_string_new_empty();
        effect = sk_runtimeeffect_make(text, error);
        std::string diagnostic = sk_string_get_c_str(error);
        sk_string_destructor(text);
        require(effect != nullptr, "SkSL compile failed: " + diagnostic);
        require(sk_runtimeeffect_get_children_count(effect) == 1, "Expected exactly one layer child");
        sk_runtimeeffect_get_child_name(effect, 0, error);
        require(std::string(sk_string_get_c_str(error)) == "svala_layer", "Unexpected child name");
        sk_string_destructor(error);
        require(sk_runtimeeffect_get_uniforms_count(effect) == 12, "Expected twelve shader arguments");
        for (int i = 0; i < 12; ++i) {
            const std::string name = "svala_arg" + std::to_string(i);
            const auto* uniform = sk_runtimeeffect_get_uniform_from_name(effect, name.c_str(), name.size());
            require(uniform && sk_runtimeeffect_uniform_get_size_in_bytes(uniform) == (i == 0 ? 8 : 16), "Shader argument ABI mismatch");
            offsets[i] = sk_runtimeeffect_uniform_get_offset(uniform);
        }
    }
    ~Program() { sk_runtimeeffect_unref(effect); }
};

struct Head { float x=0, y=0, dx=1, dy=0, power=0; };
using Heads = std::array<Head, 8>;

struct Surface {
    sk_surface_t* surface;
    sk_imageinfo_t info;
    Surface(gr_direct_context_t* gpu, int width, int height)
        : info{nullptr, width, height, RGBA_8888_SK_COLORTYPE, PREMUL_SK_ALPHATYPE} {
        surface = sk_surface_new_render_target(reinterpret_cast<gr_recording_context_t*>(gpu), false,
            &info, 0, TOP_LEFT_GR_SURFACE_ORIGIN, nullptr, false);
        require(surface && sk_surface_get_recording_context(surface), "Accelerated render target required");
    }
    ~Surface() { sk_surface_unref(surface); }
    Pixels renderHeads(const Program& program, sk_shader_t* child, float time, float style,
                       int count, const Heads& heads) {
        std::vector<unsigned char> bytes(sk_runtimeeffect_get_uniform_size(program.effect), 0);
        const float size[] = {float(info.width), float(info.height)};
        const float state[] = {time, style, float(count), 0};
        float powers[8];
        std::memcpy(bytes.data() + program.offsets[0], size, 8);
        std::memcpy(bytes.data() + program.offsets[1], state, 16);
        for (size_t i=0; i<heads.size(); ++i) {
            const float packed[] = {heads[i].x, heads[i].y, heads[i].dx, heads[i].dy};
            std::memcpy(bytes.data() + program.offsets[i+2], packed, 16);
            powers[i] = heads[i].power;
        }
        std::memcpy(bytes.data() + program.offsets[10], powers, 16);
        std::memcpy(bytes.data() + program.offsets[11], powers+4, 16);
        auto* uniforms = sk_data_new_with_copy(bytes.data(), bytes.size());
        auto* shader = sk_runtimeeffect_make_shader(program.effect, uniforms, &child, 1, nullptr, false);
        require(shader != nullptr, "Runtime shader binding failed");
        auto* paint = sk_paint_new();
        sk_paint_set_shader(paint, shader);
        sk_paint_set_blendmode(paint, SRC_SK_BLENDMODE);
        const sk_rect_t rect{0, 0, float(info.width), float(info.height)};
        sk_canvas_draw_rect(sk_surface_get_canvas(surface), &rect, paint);
        sk_surface_flush_and_submit(surface, true);
        Pixels pixels(size_t(info.width) * info.height * 4);
        require(sk_surface_read_pixels(surface, &info, pixels.data(), size_t(info.width) * 4, 0, 0), "GPU readback failed");
        sk_paint_delete(paint); sk_shader_unref(shader); sk_data_unref(uniforms);
        return pixels;
    }
    Pixels render(const Program& program, sk_shader_t* child, float time, float style, float power,
                  float tipX, float tipY, float directionX = 1, float directionY = 0) {
        Heads heads;
        heads[0] = {tipX, tipY, directionX, directionY, power};
        return renderHeads(program, child, time, style, 1, heads);
    }
};

static Pixels picture(const char* path, int width, int height) {
    Pixels pixels(size_t(width) * height * 4, 0);
    auto* space = CGColorSpaceCreateDeviceRGB();
    auto* context = CGBitmapContextCreate(pixels.data(), width, height, 8, size_t(width) * 4,
        space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    require(context != nullptr, "Cannot allocate image fixture");
    if (path && std::string(path) != "-") {
        auto* url = CFURLCreateFromFileSystemRepresentation(nullptr,
            reinterpret_cast<const UInt8*>(path), std::strlen(path), false);
        auto* source = CGImageSourceCreateWithURL(url, nullptr);
        auto* image = source ? CGImageSourceCreateImageAtIndex(source, 0, nullptr) : nullptr;
        require(image != nullptr, "Cannot decode actual HatField asset");
        double scale = std::max(double(width) / CGImageGetWidth(image), double(height) / CGImageGetHeight(image));
        double w = scale * CGImageGetWidth(image), h = scale * CGImageGetHeight(image);
        CGContextDrawImage(context, CGRectMake((width-w)*.5, (height-h)*.5, w, h), image);
        CGImageRelease(image); CFRelease(source); CFRelease(url);
    } else {
        // A synthetic dark Canvas and partial cutting stroke isolate the
        // shader; they are never app artwork or a substitute for hat geometry.
        CGContextSetRGBFillColor(context, .015, .035, .065, 1);
        CGContextFillRect(context, CGRectMake(0, 0, width, height));
        CGContextSetRGBFillColor(context, .12, .38, .44, 1);
        CGContextFillRect(context, CGRectMake(width*.1, height*.65, width*.18, height*.2));
        CGContextSetRGBStrokeColor(context, .2, .94, .84, 1);
        CGContextSetLineWidth(context, 2.2);
        CGContextMoveToPoint(context, width*.1, height*.5);
        CGContextAddLineToPoint(context, width*.4, height*.5);
        CGContextStrokePath(context);
    }
    CGContextRelease(context); CGColorSpaceRelease(space);
    return pixels;
}

static void savePNG(const Pixels& pixels, int width, int height, const std::string& path) {
    auto* provider = CGDataProviderCreateWithData(nullptr, pixels.data(), pixels.size(), nullptr);
    auto* space = CGColorSpaceCreateDeviceRGB();
    auto* image = CGImageCreate(width, height, 8, 32, size_t(width) * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big, provider, nullptr, false, kCGRenderingIntentDefault);
    auto* url = CFURLCreateFromFileSystemRepresentation(nullptr,
        reinterpret_cast<const UInt8*>(path.data()), path.size(), false);
    auto* destination = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, nullptr);
    require(image && destination, "Cannot create PNG artifact");
    CGImageDestinationAddImage(destination, image, nullptr);
    require(CGImageDestinationFinalize(destination), "Cannot write PNG artifact");
    CFRelease(destination); CFRelease(url); CGImageRelease(image); CGColorSpaceRelease(space); CGDataProviderRelease(provider);
}

static double difference(const Pixels& a, const Pixels& b) {
    require(a.size() == b.size(), "Pixel array dimensions differ");
    double result = 0;
    for (size_t i = 0; i < a.size(); ++i) if (i % 4 != 3) result += std::abs(int(a[i]) - int(b[i]));
    return result / (a.size() / 4 * 3);
}

static double regionDifference(const Pixels& a, const Pixels& b, int width, int height,
                               int centreX, int centreY, int radius) {
    double result = 0; size_t count = 0;
    for (int y = std::max(0, centreY-radius); y < std::min(height, centreY+radius); ++y)
        for (int x = std::max(0, centreX-radius); x < std::min(width, centreX+radius); ++x)
            for (int channel = 0; channel < 3; ++channel) {
                size_t i = (size_t(y)*width+x)*4+channel;
                result += std::abs(int(a[i])-int(b[i])); ++count;
            }
    return result / count;
}

static void opaque(const Pixels& frame) {
    for (size_t i = 3; i < frame.size(); i += 4) require(frame[i] == 255, "Opaque Canvas became transparent");
}

int main(int argc, char** argv) {
    try {
        require(argc == 4, "Pass shader.sksl HatField.png-or-minus outputDirectory");
        Program program(argv[1]);
        CGLPixelFormatAttribute attributes[] = {kCGLPFAAccelerated, kCGLPFAOpenGLProfile,
            static_cast<CGLPixelFormatAttribute>(kCGLOGLPVersion_3_2_Core), static_cast<CGLPixelFormatAttribute>(0)};
        CGLPixelFormatObj format = nullptr; GLint count = 0;
        require(CGLChoosePixelFormat(attributes, &format, &count) == kCGLNoError && count > 0, "No accelerated offscreen pixel format");
        CGLContextObj context = nullptr;
        require(CGLCreateContext(format, nullptr, &context) == kCGLNoError, "Cannot create GPU context");
        CGLDestroyPixelFormat(format);
        require(CGLSetCurrentContext(context) == kCGLNoError, "Cannot activate GPU context");
        const auto* interface = gr_glinterface_create_native_interface();
        require(interface && gr_glinterface_validate(interface), "Invalid Skia GL interface");
        auto* gpu = gr_direct_context_make_gl(interface);
        require(gpu != nullptr, "Skia GPU context unavailable; CPU fallback forbidden");
        std::cout << "GPU: " << glGetString(GL_RENDERER) << '\n';
        size_t checks = 14; // Child, argument count and twelve uniform ABI checks.
        for (const auto& dims : {std::pair<int,int>{900,600}, {320,720}}) {
            Surface surface(gpu, dims.first, dims.second);
            auto pixels = picture(argv[2], dims.first, dims.second);
            auto* image = sk_image_new_raster_copy(&surface.info, pixels.data(), size_t(dims.first) * 4);
            require(image != nullptr, "Cannot upload source fixture");
            auto* child = sk_image_make_shader(image, CLAMP_SK_SHADER_TILEMODE, CLAMP_SK_SHADER_TILEMODE, nullptr);
            require(child != nullptr, "Cannot create source sampler");
            const float x = dims.first*.4f, y = dims.second*.5f;
            auto unpowered = surface.render(program, child, 0, 0, 0, x, y);
            require(unpowered == pixels, "Zero torch power must preserve the Canvas exactly"); ++checks;
            require(surface.render(program, child, 37, 2, 0, x, y) == pixels,
                "Zero power changed Canvas as time/style advanced"); ++checks;
            std::vector<Pixels> styles;
            for (int style = 0; style < 3; ++style) {
                auto first = surface.render(program, child, 0, float(style), 1, x, y);
                auto later = surface.render(program, child, .27f, float(style), 1, x, y);
                for (const auto* frame : {&first, &later}) {
                    opaque(*frame); ++checks;
                }
                require(regionDifference(first, later, dims.first, dims.second, int(x), int(y), 70) > .02,
                    "Time did not animate the flame and chips"); ++checks;
                require(first == surface.render(program, child, 0, float(style), 1, x, y),
                    "Fixed shader uniforms are not deterministic"); ++checks;
                size_t tipPixel=(size_t(int(y))*dims.first+int(x))*4;
                require(first[tipPixel]>=240 && first[tipPixel+1]>=235 && first[tipPixel+2]>=215,
                    "Torch does not have a white-hot core at its declared position"); ++checks;
                require(regionDifference(first, pixels, dims.first, dims.second, 20, 20, 10)<2,
                    "Torch unexpectedly recoloured distant Canvas content"); ++checks;
                styles.push_back(first);
                std::string prefix = std::string(argv[3]) + "/" + std::to_string(dims.first) + "-style-" + std::to_string(style);
                savePNG(first, dims.first, dims.second, prefix + "-t0.png");
                savePNG(later, dims.first, dims.second, prefix + "-t027.png");
            }
            require(regionDifference(styles[0],styles[1],dims.first,dims.second,int(x),int(y),48)>.05
                && regionDifference(styles[1],styles[2],dims.first,dims.second,int(x),int(y),48)>.05,
                "Torch palette styles are visually indistinguishable"); ++checks;
            auto moved = surface.render(program, child, 0, 0, 1, dims.first*.75f, dims.second*.7f);
            require(regionDifference(moved,styles[0],dims.first,dims.second,int(x),int(y),12)>1,
                "Moving the torch failed to clear its old position"); ++checks;
            auto zeroDirection = surface.render(program, child, 0, 0, 1, x, y, 0, 0);
            require(zeroDirection == styles[0], "Zero direction did not use the finite default direction"); ++checks;
            auto corner = surface.render(program, child, 9, 1, 1, .5f, .5f, -1, -1);
            opaque(corner); ++checks;
            Heads heads;
            const int columns = dims.first > dims.second ? 4 : 2;
            const int rows = 8/columns;
            for (int i=0; i<8; ++i) heads[i] = {
                float(dims.first*(i%columns+1)/double(columns+1)),
                float(dims.second*(i/columns+1)/double(rows+1)), 1, 0, 1};
            // Keep all unused slots powered to prove count gates the real heads.
            for (int count=1; count<=8; ++count) {
                auto multiple = surface.renderHeads(program, child, .4f, 0, count, heads);
                opaque(multiple); ++checks;
                for (int i=0; i<8; ++i) {
                    int hx=int(heads[i].x), hy=int(heads[i].y);
                    size_t at=(size_t(hy)*dims.first+hx)*4;
                    if (i<count) require(multiple[at]>=240 && multiple[at+1]>=235 && multiple[at+2]>=215,
                        "Active cutter is missing at count="+std::to_string(count)+" head="+std::to_string(i));
                    else require(regionDifference(multiple,pixels,dims.first,dims.second,hx,hy,2)<2,
                        "A head beyond the selected cutter count was rendered");
                    ++checks;
                }
                if (count==1 || count==2 || count==4 || count==8)
                    savePNG(multiple,dims.first,dims.second,std::string(argv[3])+"/"+std::to_string(dims.first)+"-cutters-"+std::to_string(count)+".png");
            }
            require(surface.renderHeads(program,child,9,2,0,heads)==pixels,
                "Zero selected cutters changed the Canvas"); ++checks;
            for (auto& head:heads) head.power=0;
            require(surface.renderHeads(program,child,9,2,8,heads)==pixels,
                "Eight unpowered cutters changed the Canvas"); ++checks;
            for (auto& head:heads) head={x,y,1,0,1};
            auto overlap=surface.renderHeads(program,child,.4f,1,8,heads);
            opaque(overlap); ++checks;
            size_t at=(size_t(int(y))*dims.first+int(x))*4;
            require(overlap[at]>=240 && overlap[at+1]>=235 && overlap[at+2]>=215,
                "Overlapping cutter cores became invalid"); ++checks;
            sk_shader_unref(child); sk_image_unref(image);
        }
        gr_recording_context_unref(reinterpret_cast<gr_recording_context_t*>(gpu)); gr_glinterface_unref(interface);
        CGLSetCurrentContext(nullptr); CGLDestroyContext(context);
        std::cout << "PASS: " << checks << " ABI/offscreen GPU cases\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
}
