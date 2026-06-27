// miniaudio_bridge.c
// 实现 miniaudio_bridge.h 中定义的 C API
//
// 编译方式: 需要下载 miniaudio.h (https://github.com/mackron/miniaudio/blob/master/miniaudio.h)
// 放到同目录, 然后与本文件一起编译. miniaudio 是单头文件库, 会自动检测平台后端.
//
// 编译示例 (Windows MSVC, x64):
//   cl /O2 /LD miniaudio_bridge.c /Fe:miniaudio_bridge.dll
// 编译示例 (Linux/macOS, x86_64):
//   gcc -O2 -fPIC -shared miniaudio_bridge.c -o libminiaudio_bridge.so
//   gcc -O2 -fPIC -shared miniaudio_bridge.c -o libminiaudio_bridge.dylib
// Android (arm64):
//   $NDK/toolchains/llvm/prebuilt/.../aarch64-linux-android24-clang \
//     -O2 -fPIC -shared miniaudio_bridge.c -o libminiaudio_bridge.so
// iOS (静态库):
//   xcrun -sdk iphoneos clang -arch arm64 -O2 -fPIC \
//     -shared miniaudio_bridge.c -o libminiaudio_bridge.dylib

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include "miniaudio_bridge.h"
#include <stdlib.h>
#include <string.h>

// 内部 bridge 状态
typedef struct {
    ma_device      device;         // miniaudio 设备 (透明结构, 必须按值持有)
    ma_context     context;        // 上下文 (用于显式后端选择)
    ma_bridge_config config;       // 用户配置快照
    ma_bridge_data_proc dataCallback;
    void*          pUserData;
    int            initialized;
    int            started;
    char           backendName[64];
} ma_bridge;

// ---------------------------------------------------------------------------
// 默认配置
// ---------------------------------------------------------------------------
ma_bridge_config ma_bridge_config_init_default(void)
{
    ma_bridge_config cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.sampleRate = 48000;
    cfg.periodSizeInFrames = 256;   // 低延迟默认值
    cfg.periodCount = 2;
    cfg.channels = 2;
    cfg.format = 0;                 // f32
    cfg.backend = MA_BRIDGE_BACKEND_DEFAULT;
    cfg.wasapiExclusive = 0;
    cfg.aaudioExclusive = 0;
    cfg.noPreSilencedInputBuffer = 0;
    cfg.noClip = 1;                 // 本项目在 C# 侧用 SoftLimit, 禁用 miniaudio 内部 clip
    cfg.noDeviceStateChangedCallback = 1; // 性能优化
    return cfg;
}

// ---------------------------------------------------------------------------
// 辅助: 后端枚举转换
// ---------------------------------------------------------------------------
static ma_backend to_ma_backend(ma_bridge_backend b)
{
    switch (b) {
        case MA_BRIDGE_BACKEND_WASAPI:    return ma_backend_wasapi;
        case MA_BRIDGE_BACKEND_DSOUND:    return ma_backend_dsound;
        case MA_BRIDGE_BACKEND_WINMM:     return ma_backend_winmm;
        case MA_BRIDGE_BACKEND_COREAUDIO: return ma_backend_coreaudio;
        case MA_BRIDGE_BACKEND_AAUDIO:    return ma_backend_aaudio;
        case MA_BRIDGE_BACKEND_OPENSL:    return ma_backend_opensl;
        case MA_BRIDGE_BACKEND_PULSEAUDIO:return ma_backend_pulseaudio;
        case MA_BRIDGE_BACKEND_ALSA:      return ma_backend_alsa;
        default: return ma_backend_wasapi; // 仅作占位, 实际使用 NULL (自动)
    }
}

// ---------------------------------------------------------------------------
// 设备数据回调 (miniaudio → C#)
// miniaudio 的 ma_device_data_proc 签名:
//   void(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount)
// 转换为本桥的 ma_bridge_data_proc 签名:
//   void(void* pUserData, float* pOutput, uint32_t frameCount)
// ---------------------------------------------------------------------------
static void ma_device_callback(ma_device* pDevice,
                                void* pOutput,
                                const void* pInput,
                                ma_uint32 frameCount)
{
    ma_bridge* pBridge = (ma_bridge*)pDevice->pUserData;
    if (pBridge == NULL || pBridge->dataCallback == NULL) {
        // 回调未就绪, 输出静音
        if (pOutput != NULL) {
            memset(pOutput, 0, (size_t)frameCount * 2 * sizeof(float));
        }
        return;
    }
    pBridge->dataCallback(pBridge->pUserData, (float*)pOutput, (uint32_t)frameCount);
}

// ---------------------------------------------------------------------------
// 初始化
// ---------------------------------------------------------------------------
ma_bridge_result ma_bridge_init(const ma_bridge_config* pConfig,
                                ma_bridge_data_proc dataCallback,
                                void* pUserData,
                                void** ppBridge)
{
    if (pConfig == NULL || dataCallback == NULL || ppBridge == NULL) {
        return MA_BRIDGE_ERR_INVALID_ARG;
    }

    ma_bridge* pBridge = (ma_bridge*)calloc(1, sizeof(ma_bridge));
    if (pBridge == NULL) {
        return MA_BRIDGE_ERR_INIT;
    }

    pBridge->config = *pConfig;
    pBridge->dataCallback = dataCallback;
    pBridge->pUserData = pUserData;

    ma_result mr;

    // ---- 1. 上下文初始化 (仅当显式指定后端时使用) ----
    if (pConfig->backend != MA_BRIDGE_BACKEND_DEFAULT) {
        ma_backend backends[1] = { to_ma_backend(pConfig->backend) };
        mr = ma_context_init(backends, 1, NULL, &pBridge->context);
        if (mr != MA_SUCCESS) {
            // 回退到自动后端选择
            mr = ma_context_init(NULL, 0, NULL, &pBridge->context);
            if (mr != MA_SUCCESS) {
                free(pBridge);
                return MA_BRIDGE_ERR_INIT;
            }
        }
    }
    // 否则: 不创建显式 context, 让 ma_device_init 内部用 NULL context (自动)

    // ---- 2. 设备配置 ----
    ma_device_config devCfg = ma_device_config_init(ma_device_type_playback);
    devCfg.playback.format   = ma_format_f32;
    devCfg.playback.channels = pConfig->channels ? pConfig->channels : 2;
    devCfg.sampleRate        = pConfig->sampleRate;
    devCfg.periodSizeInFrames= pConfig->periodSizeInFrames;
    devCfg.periods           = pConfig->periodCount;   // miniaudio 字段名为 periods
    devCfg.dataCallback      = ma_device_callback;
    devCfg.pUserData         = pBridge;

    // 性能 / 兼容标志
    // noPreSilencedOutputBuffer: 回调自己填满整个输出缓冲区, 跳过 miniaudio 预清零以节省一点 CPU
    devCfg.noPreSilencedOutputBuffer = (ma_bool8)(pConfig->noPreSilencedInputBuffer ? MA_TRUE : MA_FALSE);
    // noClip: 本项目在 C# 侧用 SoftLimit 做软限幅, 禁用 miniaudio 内部硬 clip
    devCfg.noClip            = (ma_bool8)(pConfig->noClip ? MA_TRUE : MA_FALSE);

    // WASAPI 独占模式 (仅 Windows + WASAPI 后端生效)
    // 独占模式通过 shareMode 字段控制, 不是 wasapi.usage
#if defined(_WIN32) || defined(__WIN32__) || defined(WIN32)
    if (pConfig->wasapiExclusive) {
        devCfg.playback.shareMode = ma_share_mode_exclusive;
        devCfg.wasapi.usage       = ma_wasapi_usage_pro_audio;  // 提高线程优先级
    }
#endif

    // AAudio 低延迟模式 (仅 Android)
    // AAudio 没有 "exclusive" 概念, 这里使用 game usage 获取低延迟路径
#if defined(__ANDROID__)
    if (pConfig->aaudioExclusive) {
        devCfg.aaudio.usage = ma_aaudio_usage_game;
    }
#endif

    // ---- 3. 设备初始化 ----
    ma_context* pCtx = (pConfig->backend != MA_BRIDGE_BACKEND_DEFAULT) ? &pBridge->context : NULL;
    mr = ma_device_init(pCtx, &devCfg, &pBridge->device);
    if (mr != MA_SUCCESS) {
        // 如果显式后端失败, 尝试自动后端
        if (pConfig->backend != MA_BRIDGE_BACKEND_DEFAULT) {
            ma_context_uninit(&pBridge->context);
            mr = ma_device_init(NULL, &devCfg, &pBridge->device);
            if (mr != MA_SUCCESS) {
                free(pBridge);
                return MA_BRIDGE_ERR_DEVICE;
            }
        } else {
            free(pBridge);
            return MA_BRIDGE_ERR_DEVICE;
        }
    }

    pBridge->initialized = 1;

    // 记录后端名称
    const char* name = ma_get_backend_name(pBridge->device.pContext->backend);
    if (name != NULL) {
        strncpy(pBridge->backendName, name, sizeof(pBridge->backendName) - 1);
        pBridge->backendName[sizeof(pBridge->backendName) - 1] = '\0';
    } else {
        strncpy(pBridge->backendName, "unknown", sizeof(pBridge->backendName) - 1);
    }

    *ppBridge = pBridge;
    return MA_BRIDGE_OK;
}

// ---------------------------------------------------------------------------
// 启动 / 停止
// ---------------------------------------------------------------------------
ma_bridge_result ma_bridge_start(void* pBridge)
{
    ma_bridge* p = (ma_bridge*)pBridge;
    if (p == NULL || !p->initialized) {
        return MA_BRIDGE_ERR_NOT_INITIALIZED;
    }
    if (p->started) {
        return MA_BRIDGE_OK;
    }
    ma_result mr = ma_device_start(&p->device);
    if (mr != MA_SUCCESS) {
        return MA_BRIDGE_ERR_DEVICE;
    }
    p->started = 1;
    return MA_BRIDGE_OK;
}

ma_bridge_result ma_bridge_stop(void* pBridge)
{
    ma_bridge* p = (ma_bridge*)pBridge;
    if (p == NULL || !p->initialized) {
        return MA_BRIDGE_ERR_NOT_INITIALIZED;
    }
    if (!p->started) {
        return MA_BRIDGE_OK;
    }
    ma_result mr = ma_device_stop(&p->device);
    if (mr != MA_SUCCESS) {
        return MA_BRIDGE_ERR_DEVICE;
    }
    p->started = 0;
    return MA_BRIDGE_OK;
}

// ---------------------------------------------------------------------------
// 查询
// ---------------------------------------------------------------------------
ma_bridge_result ma_bridge_get_period_size(void* pBridge,
                                           uint32_t* pPeriodSize,
                                           uint32_t* pPeriodCount)
{
    ma_bridge* p = (ma_bridge*)pBridge;
    if (p == NULL || !p->initialized || pPeriodSize == NULL || pPeriodCount == NULL) {
        return MA_BRIDGE_ERR_INVALID_ARG;
    }
    *pPeriodSize = p->device.playback.internalPeriodSizeInFrames;
    *pPeriodCount = p->device.playback.internalPeriods;
    return MA_BRIDGE_OK;
}

ma_bridge_result ma_bridge_get_sample_rate(void* pBridge, uint32_t* pSampleRate)
{
    ma_bridge* p = (ma_bridge*)pBridge;
    if (p == NULL || !p->initialized || pSampleRate == NULL) {
        return MA_BRIDGE_ERR_INVALID_ARG;
    }
    *pSampleRate = p->device.sampleRate;
    return MA_BRIDGE_OK;
}

const char* ma_bridge_get_backend_name(void* pBridge)
{
    ma_bridge* p = (ma_bridge*)pBridge;
    if (p == NULL || !p->initialized) {
        return "uninitialized";
    }
    return p->backendName;
}

ma_bridge_result ma_bridge_set_volume(void* pBridge, float volume)
{
    ma_bridge* p = (ma_bridge*)pBridge;
    if (p == NULL || !p->initialized) {
        return MA_BRIDGE_ERR_NOT_INITIALIZED;
    }
    // ma_device_set_master_volume 内部原子写入, 线程安全
    ma_result mr = ma_device_set_master_volume(&p->device, volume);
    return (mr == MA_SUCCESS) ? MA_BRIDGE_OK : MA_BRIDGE_ERR_DEVICE;
}

// ---------------------------------------------------------------------------
// 销毁
// ---------------------------------------------------------------------------
void ma_bridge_uninit(void* pBridge)
{
    ma_bridge* p = (ma_bridge*)pBridge;
    if (p == NULL) {
        return;
    }
    if (p->initialized) {
        if (p->started) {
            ma_device_stop(&p->device);
            p->started = 0;
        }
        ma_device_uninit(&p->device);
        if (p->config.backend != MA_BRIDGE_BACKEND_DEFAULT) {
            ma_context_uninit(&p->context);
        }
        p->initialized = 0;
    }
    free(p);
}

// ---------------------------------------------------------------------------
// 版本
// ---------------------------------------------------------------------------
const char* ma_bridge_get_version(void)
{
    return MA_VERSION_STRING;
}
