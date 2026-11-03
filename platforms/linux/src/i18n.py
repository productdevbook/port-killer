"""Lightweight localization helper for the Linux tray application."""

import locale
import os

ZH_TRANSLATIONS = {
    # Tray menu
    "☁️ Cloudflare Tunnels ({count})": "☁️ Cloudflare 隧道 ({count})",
    "No active tunnels": "暂无活动隧道",
    "Port {port} → {url}": "端口 {port} → {url}",
    "Starting...": "启动中...",
    "📋 Copy Tunnel URL": "📋 复制隧道 URL",
    "Tunnel URL copied to clipboard!": "隧道 URL 已复制到剪贴板！",
    "💀 Stop Tunnel": "💀 停止隧道",
    "☸️ K8s Port Forward ({count})": "☸️ K8s 端口转发 ({count})",
    "No active port forwards": "暂无活动端口转发",
    "📋 Copy Local Port": "📋 复制本地端口",
    "Port {port} copied to clipboard!": "端口 {port} 已复制到剪贴板！",
    "💀 Stop Port Forward": "💀 停止端口转发",
    "🌐 Local Ports ({count})": "🌐 本地端口 ({count})",
    "No open ports": "暂无开放端口",
    "Open PortKiller Window": "打开 PortKiller 窗口",
    "Refresh Now": "立即刷新",
    "Quit PortKiller": "退出 PortKiller",
    # Notifications
    "Process Terminated": "进程已终止",
    "Process on port {port} terminated (SIGTERM).": "端口 {port} 上的进程已优雅终止 (SIGTERM)。",
    "Kill Failed": "结束失败",
    "Could not terminate PID {pid} on port {port}.": "无法终止端口 {port} 上的 PID {pid}。",
    "Process Killed": "进程已强制结束",
    "Process on port {port} force killed (SIGKILL).": "端口 {port} 上的进程已被强制结束 (SIGKILL)。",
    "Could not kill PID {pid} on port {port}.": "无法强制结束端口 {port} 上的 PID {pid}。",
    "PID {pid} copied to clipboard!": "PID {pid} 已复制到剪贴板！",
    "Action Done": "操作完成",
    "Tunnel Stopped": "隧道已停止",
    "Cloudflare Tunnel on port {port} stopped!": "端口 {port} 上的 Cloudflare 隧道已停止！",
    "Port Forward Stopped": "端口转发已停止",
    "Kubernetes port-forward for {resource} stopped!": "{resource} 的 Kubernetes 端口转发已停止！",
    "Port Forward Failed": "停止端口转发失败",
    "Could not stop port-forward for {resource} (PID {pid}).": "无法停止 {resource} (PID {pid}) 的端口转发。",
    "Process (PID {pid}) has been terminated.": "进程 (PID {pid}) 已被终止。",
    "Could not terminate PID {pid}.": "无法终止 PID {pid}。",
    "Port Copied": "端口已复制",
    "Process {target} has been terminated.": "{target}进程已被终止。",
    "Could not terminate process {target}.": "无法终止{target}进程。",
    "on port {port}": "端口 {port} 上的",
    # Window & Dialog
    "Search ports or processes...": "搜索端口或进程...",
    "Cloudflare Tunnels": "Cloudflare 隧道",
    "K8s Port Forward": "K8s 端口转发",
    "Local Ports": "本地端口",
    "No listening ports found": "未发现正在监听的端口",
    "Port {port}": "端口 {port}",
    "Namespace: {ns} | PID: {pid}": "命名空间：{ns} | PID: {pid}",
    "Copy": "复制",
    "Kill": "结束",
    "Port {port} Management": "端口 {port} 管理",
    "Process: {name}": "进程：{name}",
    "Unknown": "未知",
    "PID:      {pid}\nAddress:  {address}\nCommand:  {command}": "PID：     {pid}\n监听地址：{address}\n启动命令：{command}",
    "Kill Process (SIGTERM)": "结束进程 (SIGTERM)",
    "Force Kill (SIGKILL)": "强制结束 (SIGKILL)",
    "Copy PID": "复制 PID",
    "Copy Port": "复制端口",
    "Close": "关闭",
}


def is_chinese_locale(env=None):
    """Return True if the environment or system locale prefers Chinese."""
    environ = env if env is not None else os.environ
    for var in ("LC_ALL", "LC_MESSAGES", "LANG", "LANGUAGE"):
        val = environ.get(var, "")
        if val:
            return val.lower().startswith("zh")
    try:
        loc, _ = locale.getlocale()
        if loc and loc.lower().startswith("zh"):
            return True
    except Exception:
        pass
    return False


def tr(key, lang=None, **kwargs):
    """Translate a UI string to Simplified Chinese when in a Chinese locale."""
    use_zh = (lang == "zh") if lang is not None else is_chinese_locale()
    template = ZH_TRANSLATIONS.get(key, key) if use_zh else key
    return template.format(**kwargs) if kwargs else template
