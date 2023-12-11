//
//  LMEmulationWindow_Apple.m
//  Limon
//
//  Created by Jarrod Norwell on 10/9/23.
//

#import "LMEmulationWindow_Apple.h"

#include <algorithm>
#include <array>
#include <cstdlib>
#include <string>

#include "common/logging/log.h"
#include "common/settings.h"
#include "input_common/main.h"
#include "network/network.h"
#include "video_core/renderer_base.h"
#include "video_core/video_core.h"

EmulationWindow_Apple::EmulationWindow_Apple(CA::MetalLayer* surface, bool is_secondary, CGSize size) : Frontend::EmuWindow(is_secondary), host_window(surface), size(size) {
    is_portrait = true;
    if (!surface)
        return;
    
    window_width = size.width;
    window_height = size.height;

    Network::Init();
};

EmulationWindow_Apple::~EmulationWindow_Apple() {
    DestroyWindowSurface();
    DestroyContext();
};


void EmulationWindow_Apple::OnSurfaceChanged(CA::MetalLayer* surface) {
    render_window = surface;

    window_info.type = Frontend::WindowSystemType::MacOS;
    window_info.render_surface = surface;
    window_info.render_surface_scale = [[UIScreen mainScreen] nativeScale];

    StopPresenting();
    OnFramebufferSizeChanged();
};


void EmulationWindow_Apple::OnTouchEvent(int x, int y) {
    TouchPressed(static_cast<unsigned>(std::max(x, 0)), static_cast<unsigned>(std::max(y, 0)));
}

void EmulationWindow_Apple::OnTouchMoved(int x, int y) {
    TouchMoved(static_cast<unsigned>(std::max(x, 0)), static_cast<unsigned>(std::max(y, 0)));
}

void EmulationWindow_Apple::OnTouchReleased() {
    TouchReleased();
};


void EmulationWindow_Apple::DoneCurrent() {
    core_context->DoneCurrent();
};

void EmulationWindow_Apple::MakeCurrent() {
    core_context->MakeCurrent();
};


void EmulationWindow_Apple::StopPresenting() {};
void EmulationWindow_Apple::TryPresenting() {};


void EmulationWindow_Apple::OnFramebufferSizeChanged() {
    auto bigger{window_width > window_height ? window_width : window_height};
    auto smaller{window_width < window_height ? window_width : window_height};
    
    UpdateCurrentFramebufferLayout(is_portrait ? smaller : bigger, is_portrait ? bigger : smaller, is_portrait);
};


bool EmulationWindow_Apple::CreateWindowSurface() {
    return false;
};


void EmulationWindow_Apple::DestroyContext() {};
void EmulationWindow_Apple::DestroyWindowSurface() {};
