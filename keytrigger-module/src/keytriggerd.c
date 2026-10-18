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
        /* 父进程：不等待。子进程会被 init 收养，不会变僵尸。 */
        return;
    }

    /* 第一层子进程：再 fork 一次后立即退出，让孙子进程脱离父进程。 */
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

/* 震动反馈（异步，不等待震动结束）。
 *
 * ms  = 持续毫秒
 * amp = 振幅 1..255
 *
 * 关键：不使用 `synced`（那是同步语义），但保留它也能工作——因为我们
 * 已经不等待子进程。这里仍用 synced 以保持「同一时刻只排一个震动」
 * 的语义，避免两个震动请求互相打断。 */
static void vibrate_async(int ms, int amp)
{
    static char path[] = "/system/bin/cmd";
    static char group[] = "vibrator_manager";
    static char sync_kw[] = "synced";
    static char oneshot_kw[] = "oneshot";
    char ms_buf[16];
    char amp_buf[16];
    snprintf(ms_buf, sizeof(ms_buf), "%d", ms);
    snprintf(amp_buf, sizeof(amp_buf), "%d", amp);

    char *argv[] = {
        path,
        group,
        sync_kw,
        oneshot_kw,
        ms_buf,
        amp_buf,
        NULL,
    };
    spawn_detached(argv);
}

/* 读取 app 侧写入的录音状态：1=录音中，0=空闲/未知。 */
static int app_is_recording(void)
{
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
/* 双短震：开始录音的反馈。
 *
 * 关键：不再用「vibrate + usleep + vibrate」串联。
 * 那会产生两个问题：
 * 1) 旧 vibrate 内部同步等待震动结束，第二记被延迟、甚至偶发丢失
 *    （用户反馈的「只触发第一段」）；
 * 2) usleep 期间主循环停止 poll，按键事件被延迟。
 *
 * 现在两次 vibrate_async 连发，由系统震动服务自行排队，父进程立即返回。 */
static void vibrate_start_feedback(void)
{
    vibrate_async(45, 190);
    vibrate_async(45, 190);
}

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
        /* 停止：一记长震。 */
        vibrate_async(260, 220);
    } else {
        vibrate_start_feedback();
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
                vibrate_async(25, 120);
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
