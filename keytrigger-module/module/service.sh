#!/system/bin/sh
# keytriggerd 启动与看护。
#
# 设计要点：
# - 后台循环看护：守护进程异常退出会被自动拉起（2 秒后重试），
#   避免「长按没反应」而用户不知道原因；
# - 等待 system 就绪：开机早期 am / cmd 尚不可用，过早启动会触发失败；
# - 日志轮转由守护进程自身处理（超过 128KB 截断）。

MODULE_DIR=/data/adb/modules/feathernote-keytrigger
BIN=$MODULE_DIR/keytriggerd
LOG=$MODULE_DIR/service.log

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

# 等待系统服务就绪（最多 60 秒）。am 不可用时触发必然失败。
i=0
while [ $i -lt 60 ]; do
  if command -v am >/dev/null 2>&1 && command -v cmd >/dev/null 2>&1; then
    break
  fi
  sleep 1
  i=$((i + 1))
done
sleep 3

log "service.sh 启动看护"

# 看护循环：每 2 秒检查一次，进程不在就重新拉起。
while true; do
  if ! pgrep -f "$BIN" >/dev/null 2>&1; then
    log "keytriggerd 未运行，启动"
    "$BIN" &
  fi
  sleep 2
done
