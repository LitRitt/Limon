//
//  LMCitra.m
//  Limon
//
//  Created by Jarrod Norwell on 10/9/23.
//

#import "LMCitra.h"
#import "LMEmulationWindow_Vulkan.h"

#include "LMConfiguration.h"
#include "LMInputManager.h"

#ifdef __cplusplus
#include "audio_core/dsp_interface.h"
#include "common/dynamic_library/dynamic_library.h"
#include "common/logging/backend.h"
#include "common/logging/log.h"
#include "core/core.h"
#include "core/frontend/applets/default_applets.h"
#include "core/savestate.h"
#include "core/loader/loader.h"

#include <dlfcn.h>
#include <memory>
#endif

Core::System& core{Core::System::GetInstance()};
std::unique_ptr<LMEmulationWindow_Vulkan> window;
std::shared_ptr<Common::DynamicLibrary> vulkan_library;

#import "Limon-Swift.h"
@class EmulationSettings;


@implementation LMSaveState
-(LMSaveState *) initWithURL:(NSURL *)url title:(NSString *)title {
    if (self = [super init]) {
        self.url = url;
        self.title = title;
    } return self;
}
@end


@implementation LMCitra
-(LMCitra *) init {
    if (self = [super init]) {
        Common::Log::Initialize();
        Common::Log::Start();
        
        _gameImporter = [LMGameImporter sharedInstance];
        _gameInformation = [LMGameInformation sharedInstance];
        
        vulkan_library = std::make_shared<Common::DynamicLibrary>(dlopen("@executable_path/Frameworks/libMoltenVK.dylib", RTLD_NOW));
    } return self;
}

+(LMCitra *) sharedInstance {
    static dispatch_once_t onceToken;
    static LMCitra* sharedInstance = NULL;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[LMCitra alloc] init];
    });
    return sharedInstance;
}


-(NSMutableArray<NSString *> *) installedGamePaths {
    NSMutableArray<NSString *> *paths = @[].mutableCopy;
    
    const FileUtil::DirectoryEntryCallable ScanDir = [&paths, &ScanDir](u64*, const std::string& directory, const std::string& virtual_name) {
        std::string path = directory + virtual_name;
        if (FileUtil::IsDirectory(path)) {
            path += '/';
            FileUtil::ForeachDirectoryEntry(nullptr, path, ScanDir);
        } else {
            if (!FileUtil::Exists(path))
                return false;
            auto loader = Loader::GetLoader(path);
            if (loader) {
                bool executable{};
                const Loader::ResultStatus result = loader->IsExecutable(executable);
                if (Loader::ResultStatus::Success == result && executable) {
                    [paths addObject:[NSString stringWithCString:path.c_str() encoding:NSUTF8StringEncoding]];
                }
            }
        }
        return true;
    };
    
    ScanDir(nullptr, "", FileUtil::GetUserPath(FileUtil::UserPath::SDMCDir) + "Nintendo " "3DS/00000000000000000000000000000000/" "00000000000000000000000000000000/title/00040000");
    
    return paths;
}

-(NSMutableArray<NSString *> *) systemGamePaths {
    NSMutableArray<NSString *> *paths = @[].mutableCopy;
    
    const FileUtil::DirectoryEntryCallable ScanDir = [&paths, &ScanDir](u64*, const std::string& directory, const std::string& virtual_name) {
        std::string path = directory + virtual_name;
        if (FileUtil::IsDirectory(path)) {
            path += '/';
            FileUtil::ForeachDirectoryEntry(nullptr, path, ScanDir);
        } else {
            if (!FileUtil::Exists(path))
                return false;
            auto loader = Loader::GetLoader(path);
            if (loader) {
                bool executable{};
                const Loader::ResultStatus result = loader->IsExecutable(executable);
                if (Loader::ResultStatus::Success == result && executable) {
                    [paths addObject:[NSString stringWithCString:path.c_str() encoding:NSUTF8StringEncoding]];
                }
            }
        }
        return true;
    };
    
    ScanDir(nullptr, "", FileUtil::GetUserPath(FileUtil::UserPath::NANDDir) + "00000000000000000000000000000000/title/00040030");
    
    return paths;
}


-(void) resetSettings {
    LMConfiguration{};
    
    for (const auto& service_module : Service::service_module_map) {
        Settings::values.lle_modules.emplace(service_module.name, false);
    }
    
    // InputManager::Init();
    for(int i = 0; i < Settings::NativeButton::NumButtons; i++) {
        Common::ParamPackage param{ { "engine", "ios_gamepad" }, { "code", std::to_string(i) } };
        Settings::values.current_input_profile.buttons[i] = param.Serialize();
    }
    
    for(int i = 0; i < Settings::NativeAnalog::NumAnalogs; i++) {
        Common::ParamPackage param{ { "engine", "ios_gamepad" }, { "code", std::to_string(i) } };
        Settings::values.current_input_profile.analogs[i] = param.Serialize();
    }
    
    Input::RegisterFactory<Input::AnalogDevice>("ios_gamepad", std::make_shared<AnalogFactory>());
    Input::RegisterFactory<Input::ButtonDevice>("ios_gamepad", std::make_shared<ButtonFactory>());
    
    Settings::values.use_cpu_jit.SetValue(EmulationSettings.useCPUJIT);
    Settings::values.cpu_clock_percentage.SetValue([[NSNumber numberWithInteger:EmulationSettings.cpuClockPercentage] unsignedIntValue]);
    Settings::values.is_new_3ds.SetValue(EmulationSettings.isNew3DS);
    
    Settings::values.spirv_shader_gen.SetValue(EmulationSettings.spirvShaderGen);
    Settings::values.async_shader_compilation.SetValue(EmulationSettings.asyncShaderCompilation);
    Settings::values.async_presentation.SetValue(EmulationSettings.asyncShaderPresentation);
    Settings::values.use_hw_shader.SetValue(EmulationSettings.useHWShader);
    Settings::values.use_disk_shader_cache.SetValue(EmulationSettings.useDiskShaderCache);
    Settings::values.shaders_accurate_mul.SetValue(EmulationSettings.shadersAccurateMul);
    Settings::values.use_vsync_new.SetValue(EmulationSettings.useNewVSync);
    Settings::values.use_shader_jit.SetValue(EmulationSettings.useShaderJIT);
    Settings::values.resolution_factor.SetValue([[NSNumber numberWithInteger:EmulationSettings.resolutionFactor] unsignedIntValue]);
    Settings::values.frame_limit.SetValue(EmulationSettings.frameLimit);
    Settings::values.texture_filter.SetValue((Settings::TextureFilter)EmulationSettings.textureFilter);
    Settings::values.texture_sampling.SetValue((Settings::TextureSampling)EmulationSettings.textureSampling);
    
    Settings::values.render_3d.SetValue((Settings::StereoRenderOption)EmulationSettings.stereoRender);
    Settings::values.factor_3d.SetValue([[NSNumber numberWithInteger:EmulationSettings.factor3D] unsignedIntValue]);
    Settings::values.mono_render_option.SetValue((Settings::MonoRenderOption)EmulationSettings.monoRender);
    
    Settings::values.input_type.SetValue((AudioCore::InputType)[[NSNumber numberWithInteger:EmulationSettings.audioInputType] unsignedIntValue]);
    Settings::values.output_type.SetValue((AudioCore::SinkType)[[NSNumber numberWithInteger:EmulationSettings.audioOutputType] unsignedIntValue]);
    
    Frontend::RegisterDefaultApplets(core);
    
    core.ApplySettings();
    Settings::LogSettings();
}


-(void) setVulkanLayer:(CAMetalLayer *)layer {
    _vulkanLayer = layer;
    window = std::make_unique<LMEmulationWindow_Vulkan>((__bridge CA::MetalLayer*)_vulkanLayer, vulkan_library, false, _vulkanLayer.frame.size);
    [self setVulkanOrientation:[[UIDevice currentDevice] orientation] with:_vulkanLayer];
}

-(void) setVulkanOrientation:(UIDeviceOrientation)orientation with:(CAMetalLayer *)layer {
    _vulkanLayer = layer;
    if (_isRunning && !_isPaused) {
        window->OrientationChanged(orientation == UIDeviceOrientationPortrait, (__bridge CA::MetalLayer*)_vulkanLayer);
    }
}


-(void) setLayoutOption:(NSUInteger)option with:(CAMetalLayer *)layer {
    _vulkanLayer = layer;
    self._layoutOption = option;
    
    Settings::values.layout_option.SetValue((Settings::LayoutOption)[[NSNumber numberWithInteger:self._layoutOption] unsignedIntegerValue]);
    [self setVulkanOrientation:[[UIDevice currentDevice] orientation] with:_vulkanLayer];
}

-(void) swapScreens:(CAMetalLayer *)layer {
    _vulkanLayer = layer;
    
    Settings::values.swap_screen.SetValue(Settings::values.swap_screen.GetValue() ? false : true);
    [self setVulkanOrientation:[[UIDevice currentDevice] orientation] with:_vulkanLayer];
}


-(void) insert:(NSString *)path {
    _path = path;
    FileUtil::SetCurrentRomPath(std::string([_path UTF8String]));
    auto loader = Loader::GetLoader(std::string([_path UTF8String]));
    if(loader)
        loader->ReadProgramId(title_id);
}

-(void) pause {
    _isPaused = TRUE;
}

-(void) resume {
    _isPaused = FALSE;
}

-(void) run {
    window->MakeCurrent();
    auto _ = core.Load(*window, std::string([_path UTF8String]));
    
    _isRunning = TRUE;
    _isPaused = FALSE;
    _isLoading = FALSE;
    _isSaving = FALSE;
    
    while (_isRunning) {
        if (!_isPaused) {
            if (Settings::values.volume.GetValue() == 0)
                Settings::values.volume.SetValue(1);
            
            auto result = core.RunLoop();
        } else {
            if (Settings::values.volume.GetValue() == 1)
                Settings::values.volume.SetValue(0);
            
            window->PollEvents();
        }
        
        if (_isLoading)
            [self load];
        
        if (_isSaving)
            [self save];
    }
}


-(void) touchesBegan:(CGPoint)point {
    float h_ratio, w_ratio;
    h_ratio = window->GetFramebufferLayout().height / (_vulkanLayer.frame.size.height * [[UIScreen mainScreen] nativeScale]);
    w_ratio = window->GetFramebufferLayout().width / (_vulkanLayer.frame.size.width * [[UIScreen mainScreen] nativeScale]);
    window->OnTouchEvent((point.x) * [[UIScreen mainScreen] nativeScale] * w_ratio, ((point.y) * [[UIScreen mainScreen] nativeScale] * h_ratio));
}

-(void) touchesEnded {
    window->OnTouchReleased();
}

-(void) touchesMoved:(CGPoint)point {
    float h_ratio, w_ratio;
    h_ratio = window->GetFramebufferLayout().height / (_vulkanLayer.frame.size.height * [[UIScreen mainScreen] nativeScale]);
    w_ratio = window->GetFramebufferLayout().width / (_vulkanLayer.frame.size.width * [[UIScreen mainScreen] nativeScale]);
    window->OnTouchMoved((point.x) * [[UIScreen mainScreen] nativeScale] * w_ratio, ((point.y) * [[UIScreen mainScreen] nativeScale] * h_ratio));
}

-(BOOL) isPaused {
    return _isPaused;
}

-(BOOL) isRunning {
    return _isRunning;
}


-(NSMutableArray<LMSaveState *> *) saveStates {
    NSURL *saveStatesDirectory = [[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject] URLByAppendingPathComponent:@"states"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:saveStatesDirectory.path]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:saveStatesDirectory.path withIntermediateDirectories:FALSE attributes:NULL error:NULL];
    }
    
    NSURL *saveStateForGameFolder = [saveStatesDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"%llu", title_id]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:saveStateForGameFolder.path]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:saveStateForGameFolder.path withIntermediateDirectories:FALSE attributes:NULL error:NULL];
    }
    
    NSMutableArray<LMSaveState *> *paths = @[].mutableCopy;
    [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:saveStateForGameFolder.path error:NULL] enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL *stop) {
        NSURL *url = [saveStateForGameFolder URLByAppendingPathComponent:obj];
        
        NSDictionary<NSFileAttributeKey, id> *dictionary = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:NULL];
        NSDate *date = [dictionary objectForKey:NSFileCreationDate];
        
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateStyle:NSDateFormatterShortStyle];
        [formatter setTimeStyle:NSDateFormatterShortStyle];
        
        [paths addObject:[[LMSaveState alloc] initWithURL:[saveStateForGameFolder URLByAppendingPathComponent:obj] title:[formatter stringFromDate:date]]];
    }];
    
    return paths;
}

-(void) prepareForLoad {
    _isLoading = TRUE;
    _isPaused = TRUE;
}

-(void) prepareForSave {
    _isSaving = TRUE;
    _isPaused = TRUE;
}

-(void) load:(NSURL *)url {
    _savePath = url;
}

-(void) load {
    //Core::LoadState([_savePath.path UTF8String]);
    
    _isLoading = FALSE;
    _isPaused = FALSE;
}

-(void) save {
    NSURL *saveStatesDirectory = [[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject] URLByAppendingPathComponent:@"states"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:saveStatesDirectory.path]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:saveStatesDirectory.path withIntermediateDirectories:FALSE attributes:NULL error:NULL];
    }
    
    NSURL *saveStateForGameFolder = [saveStatesDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"%llu", title_id]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:saveStateForGameFolder.path]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:saveStateForGameFolder.path withIntermediateDirectories:FALSE attributes:NULL error:NULL];
    }
    
    //Core::SaveState([[saveStateForGameFolder URLByAppendingPathComponent:[NSUUID UUID].UUIDString].path UTF8String], title_id);
    
    _isSaving = FALSE;
    _isPaused = FALSE;
}
@end
