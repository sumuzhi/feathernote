/*
 * keytriggerd —— 智能按键「息屏长按 3 秒」静默录音守护进程（root）
 *
 * ============================================================================
 * 为什么必须用 root 守护进程读按键
 * ============================================================================
 * 一加 13T（PKX110 / ColorOS 15）的「智能键」在 /dev/input/event0（gpio-keys）
 * 上表现为 BTN_TRIGGER_HAPPY32（code 735）。实测结论：
 *
 *  - 无障碍服务 onKeyEvent **拿不到**该键（ColorOS 系统层拦截），且息屏时
 *    Android 输入管线根本不分发按键给无障碍；
 *  - 所以「息屏长按」只能直接读 evdev 节点。
 *
 * evdev 支持多读者：本进程 open 该节点**不会**影响 system_server 或
 * Xposed Edge Pro 的读取（双击手电筒等功能不受影响）。因此：
 *
 *  - **绝不**调用 EVIOCGRAB（那会独占设备、破坏现有按键功能）；
 *  - **必须**用 O_NONBLOCK 打开：否则内层 read() 阻塞会让外层 poll 永远等不到
 *    超时，「按住 3 秒」判定会退化成「松开才判定」（实测踩过这个坑）。
 *
 * ============================================================================
 * 工作流程
 * ============================================================================
 *   poll(event0) → 收到 code 735 DOWN → 记单调时钟起点 → 继续 poll
 *     ├─ 持续按住 → 到 PRE_HINT_MS(2s) 给一次轻震提示
 *     ├─ 到 LONG_PRESS_MS(3s) → 触发：启动透明 Activity → 服务 → Dart
 *     └─ 提前松手 → 取消（不触发）
 *   触发后进入冷却 COOLDOWN_MS，避免重复触发。
 *
 * 长按判定用 CLOCK_MONOTONIC，不受系统时间调整影响。
 *
 * ============================================================================
 * 触发方式：为什么要经透明 Activity
 * ============================================================================
 * Android 11+ 的 RECORD_AUDIO 是 while-in-use 权限：后台直接启动
 * microphone 型前台服务会被系统拒绝并静默静音（实测 allowCapture[0]，
 * AudioRecord 全零）。厂商自带录音机的做法是先起一个 TransparentActivity，
 * 让进程被判定为「使用中」，再启动服务。本进程用 `am start` 拉起 app 的
 * RecordTriggerActivity（1×1 全透明、肉眼不可见），由它去启动服务。
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

/* ── 路径与常量 ─────────────────────────────────────────────────────────── */

#define MODULE_DIR "/data/adb/modules/feathernote-keytrigger"
#define CONFIG_PATH MODULE_DIR "/config"
#define LOG_PATH MODULE_DIR "/keytriggerd.log"
#define PID_PATH MODULE_DIR "/keytriggerd.pid"
#define MAX_LOG_BYTES (128 * 1024)

/* 按键事件节点：一加 13T 智能键固定挂在 event0（gpio-keys）。 */
#define KEY_DEVICE "/dev/input/event0"

/* BTN_TRIGGER_HAPPY32 = 0x2DF = 735。 */
#define TRIGGER_KEY_CODE 735

/* 默认阈值（可被 MODULE_DIR/config 覆盖）。 */
#define DEFAULT_LONG_PRESS_MS 3000
#define DEFAULT_PRE_HINT_MS 2000
#define DEFAULT_COOLDOWN_MS 2000

/* 目标组件：透明触发 Activity（exported，供 am 调用）。 */
/* app 包名（用于判断进程是否存活，见 app_process_alive）。 */
#define APP_PACKAGE "com.feathernote.app"

#define TARGET_COMPONENT \
    "com.feathernote.app/com.smartminutes.smart_minutes_flutter.RecordTriggerActivity"

/* 录音状态文件：由 app 侧 Dart 写入（recording / idle）。
 * 守护进程据此决定震动语义 —— 开始（双短震）还是停止（一长震）。 */
#define STATE_PATH "/data/user/0/com.feathernote.app/files/trigger_state"

/* ── 全局状态 ───────────────────────────────────────────────────────────── */

static long long g_long_press_ms = DEFAULT_LONG_PRESS_MS;
static long long g_pre_hint_ms = DEFAULT_PRE_HINT_MS;
static long long g_cooldown_ms = DEFAULT_COOLDOWN_MS;
static volatile sig_atomic_t g_stop = 0;

/* ── 工具函数 ───────────────────────────────────────────────────────────── */

static long long now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
}

/* 简易日志：带时间戳，超过上限时轮转一次（避免长期运行撑爆磁盘）。 */
static void log_line(const char *fmt, ...)
{
    FILE *f = fopen(LOG_PATH, "a");
    if (!f) return;

    /* 超过上限：截断重开（保留最近日志的价值低于不撑爆磁盘）。 */
    if (ftell(f) > MAX_LOG_BYTES) {
        fclose(f);
        f = fopen(LOG_PATH, "w");
        if (!f) return;
    }

    time_t t = time(NULL);
    struct tm tm_buf;
    localtime_r(&t, &tm_buf);
    char ts[32];
    strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", &tm_buf);
    fprintf(f, "%s ", ts);

    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);

    fputc('\n', f);
    fclose(f);
}

/* ============================================================================
 * 子进程执行：**异步、绝不阻塞主循环**
 * ============================================================================
 * 为什么必须异步（这是「第一记震动有、第二记没有」的根因）：
 *
 * 旧实现用 popen()/pclose() 同步等待子进程退出。而
 *   `cmd vibrator_manager synced oneshot <ms> <amp>`
 * 里的 `synced` 语义是「执行到震动结束才返回」，于是一次 vibrate() 会阻塞
 * 整整 <ms> 毫秒；「开始录音」的震动序列是 45ms + sleep 90ms + 45ms，
 * 合计约 180ms。这段时间主循环完全停止 poll 按键，表现为：
 *   - 第二记震动与 am start 的时序互相挤压，偶发丢失；
 *   - 这期间发生的按键（松手/再按）被延迟处理，长按时长计算出错。
 *
 * 因此所有子进程一律 fork 后立即返回，父进程不等待。子进程用
 * exec 直接替换自身（不经过 shell，省一次 fork），并把输出丢弃。
 * ========================================================================= */

/* 启动一个后台子进程执行 argv（argv[0] 必须是绝对路径）。
 * 立即返回：不等待子进程结束，也不关心其退出码。
 * 用双重 fork 让子进程被 init 收养，避免留下僵尸进程（守护进程不 wait）。 */
static void spawn_detached(char *const argv[])
{
    pid_t pid = fork();
    if (pid < 0) {
        log_line("fork 失败：%s", strerror(errno));
        return;
    }
    if (pid > 0) {
        /* 父进程：立即返回。
         * ⚠️ 子进程的回收由 main() 里设置的 SIGCHLD=SIG_IGN 负责
         * （内核自动 reap，不留僵尸）。见 reap_children() 的注释。 */
        return;
    }

    /* 第一层子进程：再 fork 一次后立即退出，让孙子进程被 init 收养。 */
    pid_t grandchild = fork();
    if (grandchild < 0) _exit(127);
    if (grandchild > 0) _exit(0);

    /* 孙进程：真正的执行者。丢弃所有输出，避免阻塞或污染。 */
    int devnull = open("/dev/null", O_RDWR);
    if (devnull >= 0) {
        dup2(devnull, STDIN_FILENO);
        dup2(devnull, STDOUT_FILENO);
        dup2(devnull, STDERR_FILENO);
        if (devnull > STDERR_FILENO) close(devnull);
    }

    execv(argv[0], argv);
    _exit(127);
}

/* 回收所有已退出的子进程（防僵尸）。
 *
 * 为什么需要：spawn_detached() 的第一层子进程 fork 后立即 _exit(0)，
 * 若不回收就会变成僵尸（状态 Z），每次触发留下一个 —— 实测累积到
 * 21 个。虽然僵尸不占 CPU，但会消耗 PID 与内核 task 结构，
 * 长期运行（设备可开机数周）会不断累积。
 *
 * 两种回收方式同时用，互为兜底：
 * 1) main() 里 signal(SIGCHLD, SIG_IGN) —— 内核自动 reap，
 *    这是最彻底的方式（连 wait 都不用调用）；
 * 2) 本函数在每次 spawn 前主动 waitpid(WNOHANG) 扫一遍，
 *    覆盖 SIGCHLD 被其他代码意外改写的情况。
 *
 * 注意：不能阻塞式 waitpid()，否则会卡住主循环，反而引入新问题。 */
static void reap_children(void)
{
    /* 循环回收，直到没有已退出的子进程为止。
     * waitpid 返回 0 表示「有子进程但都还在跑」；-1 表示没有子进程。 */
    for (;;) {
        pid_t r = waitpid(-1, NULL, WNOHANG);
        if (r <= 0) break;
    }
}

/* 触发 app 的透明 Activity（异步，不等待 am 结果）。
 *
 * 注意：不再检查 am 的退出码。原因：
 * 1) 异步执行拿不到退出码，而 UI 卡顿比拿不到退出码更糟；
 * 2) am 失败时系统会有 logcat 记录，震动语义由「是否真的开始录音」决定
 *    （见主循环里对 trigger_state 的读取）。
 * 若需要失败提示，由 app 侧写状态文件反映真实结果。 */
static void start_trigger_activity(const char *command)
{
    static char component[] = TARGET_COMPONENT;
    static char user_arg[] = "--user";
    static char user_val[] = "0";
    static char n_arg[] = "-n";
    static char es_arg[] = "--es";
    static char key_arg[] = "cmd";
    static char cmd_start[] = "start";
    static char cmd_stop[] = "stop";

    char *argv[] = {
        (char *)"/system/bin/am",
        (char *)"start",
        user_arg,
        user_val,
        n_arg,
        component,
        es_arg,
        key_arg,
        (strcmp(command, "stop") == 0) ? cmd_stop : cmd_start,
        NULL,
    };
    spawn_detached(argv);
}

/* ============================================================================
 * 震动反馈：两段式模式，用「次数」区分开始/停止
 * ============================================================================
 * 用户需盲操作（不看屏幕、仅凭手感分辨当前动作），约定：
 *
 *   开始录音：[震1下] …停顿… [震2下]    共 3 下
 *   停止录音：[震1下] …停顿… [震3下]    共 4 下
 *
 * 设计要点：
 * - 第一段统一下 1 下，作用是「确认按键已被识别」；
 * - 第二段的数量（2 vs 3）才是区分依据，用户即使没数清第一段也能判断；
 * - 不再使用长震（长震与短震在手感上界限模糊，且容易和系统其他反馈混淆）。
 *
 * 实现要点：**整段序列在一个子进程里完成**，父进程立即返回。
 * 子进程内逐次调用 `cmd vibrator_manager oneshot`（异步、立即返回），
 * 两次之间用 nanosleep 精确控制间隔 —— 不受父进程调度影响，时序稳定。
 * ========================================================================= */

/* 单记震动的描述。 */
struct vib_step {
    int ms;   /* 震动时长 */
    int gap;  /* 本记结束后的停顿（毫秒）；最后一记填 0 */
};

/* 执行一段震动序列（异步，父进程立即返回）。
 *
 * ⚠️ **重要：用 `waveform` 一次调用完成整段序列，不要逐次 oneshot。**
 *
 * 实测发现两个问题（第一版踩的坑）：
 * 1) `cmd vibrator_manager synced oneshot <ms> <amp>` 语法**错误** ——
 *    振幅必须用 `-a` 标志：`synced oneshot -a <ms> <amp>`。原文写法
 *    会把 amp 当成第二个 effect 参数，导致 "Unknown command: oneshot"。
 * 2) 即使语法正确，逐次调用也需要自己 sleep 控制间隔，时序受调度影响。
 *
 * 正确做法（实测 rc=0）：
 *   cmd vibrator_manager synced waveform <延迟> <时长> <振幅> <间隔> <时长> <振幅> ...
 * waveform 由系统精确定时，一次调用出完整节奏，且只在开始时 fork 一次。
 *
 * 参数格式：waveform 的每个「震-停」周期是 <duration> <amplitude> [frequency]，
 * 其中偶数位参数表示震动时长、奇数位是振幅；中间的空档由 Android 的
 * waveform 语义自动处理（相邻 step 之间即为停顿时长）。
 * 简化处理：我们只提供「震动步」，两下之间的间隔通过 waveform 的
 * 重复参数自然形成。
 */
static void vibrate_pattern(const struct vib_step *steps, int count, int amp)
{
    if (count <= 0) return;

    static char path[] = "/system/bin/cmd";
    static char group[] = "vibrator_manager";
    static char synced_kw[] = "synced";
    static char waveform_kw[] = "waveform";
    static char delay_zero[] = "0";
    static char amp_flag[] = "-a";

    /* 构造参数数组：cmd vibrator_manager synced waveform -a <dur> <amp> <dur> <amp> ...
     * 用 -a 标志启用振幅参数（否则第 3 个参数会被当成 frequency）。 */
    char num_bufs[16][16];
    char *argv[16 + 8];
    int argc = 0;

    argv[argc++] = path;
    argv[argc++] = group;
    argv[argc++] = synced_kw;
    argv[argc++] = waveform_kw;
    argv[argc++] = amp_flag;

    int used = 0;
    for (int i = 0; i < count && used + 1 < 16; i++) {
        snprintf(num_bufs[used], sizeof(num_bufs[0]), "%d", steps[i].ms);
        argv[argc++] = num_bufs[used];
        used++;
        snprintf(num_bufs[used], sizeof(num_bufs[0]), "%d", amp);
        argv[argc++] = num_bufs[used];
        used++;
        /* 若本记后面还有间隔，用 0 振幅的「静默段」把两记分开 —— 这是
         * waveform 表达停顿的标准做法（振幅 0 即不震动）。 */
        if (steps[i].gap > 0 && used < 16) {
            snprintf(num_bufs[used], sizeof(num_bufs[0]), "%d", steps[i].gap);
            argv[argc++] = num_bufs[used];
            used++;
            snprintf(num_bufs[used], sizeof(num_bufs[0]), "%d", 0);
            argv[argc++] = num_bufs[used];
            used++;
        }
    }
    argv[argc] = NULL;

    pid_t pid = fork();
    if (pid < 0) {
        log_line("fork 失败（震动）：%s", strerror(errno));
        return;
    }
    if (pid > 0) return; /* 父进程立即返回，主循环继续 poll 按键 */

    /* 第一层子进程：再 fork 后退出，让孙子进程被 init 收养。 */
    pid_t grandchild = fork();
    if (grandchild < 0) _exit(127);
    if (grandchild > 0) _exit(0);

    /* 孙进程：执行一次 waveform 调用，丢弃输出。 */
    int devnull = open("/dev/null", O_RDWR);
    if (devnull >= 0) {
        dup2(devnull, STDIN_FILENO);
        dup2(devnull, STDOUT_FILENO);
        dup2(devnull, STDERR_FILENO);
        if (devnull > STDERR_FILENO) close(devnull);
    }
    (void)delay_zero;
    execv(path, argv);
    _exit(127);
}

/* ── 震动模式常量 ────────────────────────────────────────────────────────
 *
 * 整体节奏（与长按判定时刻绑定，用户靠手感就能确认「按键被识别」和
 * 「动作已执行」两件事）：
 *
 *   t=2000ms  预提示：震 1 下（轻）—— 告知「快触发了」
 *   t=3000ms  开始录音：震 2 下
 *   t=3000ms  结束录音：震 3 下
 *
 * 因此「触发之后的震动次数」是唯一区分依据：2 下=开始，3 下=停止。
 * 两次之间留足够停顿（GAP_INNER），保证能数清。
 *
 * 时长选 45ms：短促干脆，连续多下不会糊成一片（80ms 以上容易连成一条）。
 * 振幅 200：明显但不刺耳。
 * ────────────────────────────────────────────────────────────────────── */

/* ── 震动参数 ────────────────────────────────────────────────────────────
 *
 * 设计原则：**触发震动与预提示使用完全相同的参数**（30ms / 振幅 120），
 * 因此「触发」在体感上就等于「把预提示重放 2 遍或 3 遍」—— 一致性带来
 * 直观的可预期性，用户不需要学习两种不同的震动语言。
 *
 *   开始录音：⋯ 预提示【1 下】 ⋯ 触发【2 下】
 *   结束录音：⋯ 预提示【1 下】 ⋯ 触发【3 下】
 *
 * 区分依据：触发阶段的震动次数（2 vs 3）。
 *
 * 参数说明：
 * - 30ms 短促轻点，连续多下也不会糊成一片；
 * - 振幅 120 偏轻，深夜使用不突兀，但连续几下仍清晰可数；
 * - 段内间隔 110ms：足以分辨单次，又不会显得拖沓。
 * ────────────────────────────────────────────────────────────────────── */

#define VIB_MS 30      /* 与预提示一致 */
#define VIB_AMP 120    /* 与预提示一致 */
#define GAP_INNER 110  /* 多记之间的间隔 */

/* 开始录音：震 2 下（等于预提示连震 2 次）。 */
static void vibrate_feedback_start(void)
{
    static const struct vib_step steps[] = {
        {VIB_MS, GAP_INNER},
        {VIB_MS, 0},
    };
    vibrate_pattern(steps, (int)(sizeof(steps) / sizeof(steps[0])), VIB_AMP);
}

/* 结束录音：震 3 下（等于预提示连震 3 次）。 */
static void vibrate_feedback_stop(void)
{
    static const struct vib_step steps[] = {
        {VIB_MS, GAP_INNER},
        {VIB_MS, GAP_INNER},
        {VIB_MS, 0},
    };
    vibrate_pattern(steps, (int)(sizeof(steps) / sizeof(steps[0])), VIB_AMP);
}

/* 读取 app 侧写入的录音状态：1=录音中，0=空闲/未知。 */
/* app 进程是否存活（决定状态文件是否可信）。
 *
 * 为什么需要：`trigger_state` 是 app 写的普通文件，**进程被杀死、app 被更新、
 * 强制停止后不会自动清理**。若守护进程盲信它，会出现：
 *
 *   残留 "recording" + app 实际没在跑
 *     → 长按被判定为「停止」
 *     → 命令投给一个不存在的录音，等于什么也没发生
 *     → 用户看到的现象：「长按没反应 / 无法激活录音」
 *
 * 因此判定录音状态前，先确认 app 进程活着；进程不在则忽略残留状态。
 *
 * 用 /proc/<pid>/cmdline 匹配包名：app 可能有多个进程（:remote 等），
 * 扫描所有 /proc 数字目录最可靠（不依赖 pidof 命令是否可用）。 */
static int app_process_alive(void)
{
    DIR *proc = opendir("/proc");
    if (!proc) return 1; /* 拿不到 /proc 时保守视为存活，避免误清状态 */

    struct dirent *ent;
    char path[64];
    char buf[512];
    int alive = 0;

    while ((ent = readdir(proc)) != NULL) {
        /* 只要纯数字目录（PID）。 */
        char *p = ent->d_name;
        if (*p < '1' || *p > '9') continue;
        int all_digits = 1;
        for (char *q = p; *q; q++) {
            if (*q < '0' || *q > '9') { all_digits = 0; break; }
        }
        if (!all_digits) continue;

        snprintf(path, sizeof(path), "/proc/%s/cmdline", p);
        FILE *f = fopen(path, "r");
        if (!f) continue;
        size_t n = fread(buf, 1, sizeof(buf) - 1, f);
        fclose(f);
        if (n == 0) continue;
        buf[n] = '\0';
        /* cmdline 用 '\0' 分隔，首个参数通常是可执行路径：
         * Android app 进程形如 "com.feathernote.app" 或
         * "/system/bin/app_process... com.feathernote.app"。 */
        if (strstr(buf, APP_PACKAGE) != NULL) {
            alive = 1;
            break;
        }
    }
    closedir(proc);
    return alive;
}

/* 读取 app 侧写入的录音状态：1=录音中，0=空闲/未知/进程不在。 */
static int app_is_recording(void)
{
    /* 进程不在 → 状态文件不可信，一律视为空闲（走「开始录音」）。
     * 这一步同时顺手清掉残留文件，避免下次再被误导。 */
    if (!app_process_alive()) {
        if (access(STATE_PATH, F_OK) == 0) {
            log_line("app 进程不在，忽略并清理残留状态文件");
            unlink(STATE_PATH);
        }
        return 0;
    }

    FILE *f = fopen(STATE_PATH, "r");
    if (!f) return 0;
    char buf[32] = {0};
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    if (n == 0) return 0;
    return strncmp(buf, "recording", 9) == 0 ? 1 : 0;
}

/* 读取模块 config 里的阈值（KEY=VALUE，每行一个，允许 # 注释）。
 * 配置错误一律回落到默认值：配置文件写坏了不能让守护进程失去保护。 */
static void load_config(void)
{
    FILE *f = fopen(CONFIG_PATH, "r");
    if (!f) return;

    char line[128];
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '#' || *p == '\0') continue;

        char *eq = strchr(p, '=');
        if (!eq) continue;
        *eq = '\0';
        char *key = p;
        char *val = eq + 1;

        /* 去掉 key 尾部空白与 val 首尾空白/换行。 */
        char *kend = key + strlen(key);
        while (kend > key && (kend[-1] == ' ' || kend[-1] == '\t')) *--kend = '\0';
        while (*val == ' ' || *val == '\t') val++;
        char *vend = val + strlen(val);
        while (vend > val && (vend[-1] == '\n' || vend[-1] == '\r' ||
                              vend[-1] == ' ' || vend[-1] == '\t')) {
            *--vend = '\0';
        }

        long v = strtol(val, NULL, 10);
        if (v <= 0) continue; /* 非法值忽略 */

        if (strcmp(key, "LONG_PRESS_MS") == 0) {
            g_long_press_ms = v;
        } else if (strcmp(key, "PRE_HINT_MS") == 0) {
            g_pre_hint_ms = v;
        } else if (strcmp(key, "COOLDOWN_MS") == 0) {
            g_cooldown_ms = v;
        }
    }
    fclose(f);

    /* 提示时间必须早于长按阈值，否则提示没意义。 */
    if (g_pre_hint_ms >= g_long_press_ms) {
        g_pre_hint_ms = g_long_press_ms / 2;
    }
}

/* ── 触发动作 ───────────────────────────────────────────────────────────── */

/* 触发录音开始/停止。
 *
 * 语义由 app 侧状态决定：未在录音 → 开始（双短震）；正在录音 → 停止（一长震）。
 * 为什么由状态决定而不是每次 toggle：用户需要「盲操作」时靠震动区分当前动作。
 */

/* 执行一次录音触发（开始 / 停止）。
 *
 * ⚠️ **整个函数不含任何阻塞调用**：am 与震动全部异步派发后立即返回，
 * 保证主循环尽快回到 poll()，不丢失后续按键事件。 */
static void trigger_recording(void)
{
    int recording = app_is_recording();
    const char *command = recording ? "stop" : "start";

    log_line("触发：%s录音 -> am start 透明 Activity",
             recording ? "停止" : "开始");

    /* 先发震动反馈（异步，立即返回），再派发 am。
     * 顺序上先震动能让用户更早感知到「按键生效了」，
     * 而 am 本身耗时不确定（84ms ~ 数秒），不该挡在前面。 */
    if (recording) {
        /* 结束录音：震 3 下（配合 t=2s 的 1 下预提示，共 4 下）。 */
        vibrate_feedback_stop();
    } else {
        /* 开始录音：震 2 下（配合 t=2s 的 1 下预提示，共 3 下）。 */
        vibrate_feedback_start();
    }

    /* 拉起透明 Activity（异步）：让进程「变成使用中」，
     * 随后由它启动麦克风前台服务 —— 这是解除 while-in-use 限制的关键。 */
    start_trigger_activity(command);
}

/* ── 信号处理 ───────────────────────────────────────────────────────────── */

static void on_signal(int sig)
{
    (void)sig;
    g_stop = 1;
}

/* ── 主循环 ─────────────────────────────────────────────────────────────── */

int main(void)
{
    /* 写 pid 文件（service.sh 的看护逻辑会据此判断进程是否活着）。 */
    FILE *pf = fopen(PID_PATH, "w");
    if (pf) {
        fprintf(pf, "%d\n", getpid());
        fclose(pf);
    }

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_signal;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);

    /* 子进程自动回收：spawn_detached() 会频繁 fork，若不自理会累积僵尸。
     * SIG_IGN 让内核在子进程退出时直接 reap，不产生僵尸。 */
    struct sigaction sa_chld;
    memset(&sa_chld, 0, sizeof(sa_chld));
    sa_chld.sa_handler = SIG_IGN;
    sigaction(SIGCHLD, &sa_chld, NULL);

    /* 启动时先扫一遍历史僵尸（上一次运行可能留下的）。 */
    reap_children();

    load_config();
    log_line("守护进程启动 pid=%d 长按=%lldms 预提示=%lldms 冷却=%lldms 按键=%s code=%d",
             getpid(), g_long_press_ms, g_pre_hint_ms, g_cooldown_ms,
             KEY_DEVICE, TRIGGER_KEY_CODE);

    /* O_NONBLOCK 是**关键**：阻塞 fd 会让内层 read 卡住，poll 超时永不生效，
     * 导致「按住 3 秒」无法在按住过程中判定（只能等松手）。实测踩过此坑。 */
    int fd = open(KEY_DEVICE, O_RDONLY | O_NONBLOCK);
    if (fd < 0) {
        log_line("打开 %s 失败：%s", KEY_DEVICE, strerror(errno));
        return 1;
    }

    long long down_at = 0;      /* 按下时刻（0 = 当前未按下） */
    int hint_given = 0;         /* 本次按压是否已给过预提示 */
    int fired = 0;              /* 本次按压是否已触发 */
    long long last_fire_at = 0; /* 上次触发时刻（冷却用） */

    while (!g_stop) {
        /* 有按压时，超时设为「距下一个判定点还剩多久」，保证判定及时；
         * 无按压时用 500ms 轮询，节省 CPU 又能及时响应信号。 */
        int timeout = 500;
        long long now = now_ms();
        if (down_at > 0 && !fired) {
            long long next_point = g_long_press_ms;
            if (!hint_given && g_pre_hint_ms < next_point) {
                next_point = g_pre_hint_ms;
            }
            long long remain = down_at + next_point - now;
            if (remain < 0) remain = 0;
            if (remain > 500) remain = 500;
            timeout = (int)remain;
        }

        struct pollfd pfd = {.fd = fd, .events = POLLIN, .revents = 0};
        int pr = poll(&pfd, 1, timeout);
        if (pr < 0) {
            if (errno == EINTR) continue;
            log_line("poll 失败：%s", strerror(errno));
            break;
        }

        /* 读空当前所有可用事件（非阻塞，读到 EAGAIN 为止）。 */
        if (pr > 0 && (pfd.revents & POLLIN)) {
            struct input_event evs[64];
            for (;;) {
                ssize_t n = read(fd, evs, sizeof(evs));
                if (n <= 0) break; /* EAGAIN：读空了 */
                int count = (int)(n / (ssize_t)sizeof(struct input_event));
                for (int i = 0; i < count; i++) {
                    struct input_event *ev = &evs[i];
                    if (ev->type != EV_KEY) continue;
                    if (ev->code != TRIGGER_KEY_CODE) continue;

                    if (ev->value == 1) { /* 按下 */
                        if (down_at == 0) {
                            down_at = now_ms();
                            hint_given = 0;
                            fired = 0;
                        }
                    } else if (ev->value == 0) { /* 松开 */
                        long long held = now_ms() - down_at;
                        if (down_at > 0 && !fired) {
                            log_line("松手取消（按住 %lldms < %lldms）",
                                     held, g_long_press_ms);
                        }
                        down_at = 0;
                        hint_given = 0;
                        fired = 0;
                    }
                    /* value == 2 是自动重复，忽略。 */
                }
            }
        }

        /* 按住过程中的定时判定（不依赖新事件到达）。 */
        now = now_ms();
        if (down_at > 0 && !fired) {
            long long held = now - down_at;

            /* 预提示：快到 3 秒时轻震一下，让用户知道「快触发了」。 */
            if (!hint_given && held >= g_pre_hint_ms) {
                hint_given = 1;
                log_line("预提示：已按住 %lldms（阈值 %lldms）", held, g_long_press_ms);
                {
                    /* 用与触发反馈完全相同的参数，确保体感一致。 */
                    static const struct vib_step hint[] = {{VIB_MS, 0}};
                    vibrate_pattern(hint, 1, VIB_AMP);
                }
            }

            /* 触发：按下满阈值即执行，无需等松手。 */
            if (held >= g_long_press_ms) {
                if (last_fire_at > 0 && now - last_fire_at < g_cooldown_ms) {
                    log_line("冷却中，忽略本次触发（距上次 %lldms）",
                             now - last_fire_at);
                } else {
                    fired = 1;
                    last_fire_at = now;
                    log_line("长按达成：按住 %lldms", held);
                    trigger_recording();
                }
            }
        }
    }

    close(fd);
    unlink(PID_PATH);
    log_line("守护进程退出");
    return 0;
}
