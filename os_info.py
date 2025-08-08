#!/usr/bin/env python3
import json
import os
import platform
import shutil
import socket
import sys
import time
from typing import Dict, Any


def read_first_line(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return f.readline().strip()
    except Exception:
        return ""


def parse_os_release() -> Dict[str, str]:
    result: Dict[str, str] = {}
    try:
        with open("/etc/os-release", "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                value = value.strip().strip('"')
                result[key] = value
    except Exception:
        pass
    return result


def get_primary_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        try:
            return socket.gethostbyname(socket.gethostname())
        except Exception:
            return ""


def parse_cpu_model() -> str:
    try:
        with open("/proc/cpuinfo", "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                if line.lower().startswith("model name"):
                    return line.split(":", 1)[1].strip()
    except Exception:
        pass
    return ""


def parse_meminfo() -> Dict[str, int]:
    meminfo: Dict[str, int] = {}
    try:
        with open("/proc/meminfo", "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                if ":" in line:
                    key, value = line.split(":", 1)
                    value = value.strip().split()[0]
                    if value.isdigit():
                        meminfo[key] = int(value) * 1024
    except Exception:
        pass
    return meminfo


def get_uptime_seconds() -> float:
    try:
        content = read_first_line("/proc/uptime")
        if content:
            return float(content.split()[0])
    except Exception:
        pass
    return 0.0


def seconds_to_dhms(seconds: float) -> str:
    seconds_int = int(seconds)
    days, rem = divmod(seconds_int, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, secs = divmod(rem, 60)
    parts = []
    if days:
        parts.append(f"{days}d")
    if hours or days:
        parts.append(f"{hours}h")
    if minutes or hours or days:
        parts.append(f"{minutes}m")
    parts.append(f"{secs}s")
    return " ".join(parts)


def count_processes() -> int:
    try:
        return sum(1 for name in os.listdir("/proc") if name.isdigit())
    except Exception:
        return 0


def gather_os_info() -> Dict[str, Any]:
    os_release = parse_os_release()
    meminfo = parse_meminfo()
    disk = shutil.disk_usage("/")

    info: Dict[str, Any] = {
        "hostname": socket.gethostname(),
        "primary_ip": get_primary_ip(),
        "platform": {
            "system": platform.system(),
            "node": platform.node(),
            "release": platform.release(),
            "version": platform.version(),
            "machine": platform.machine(),
            "processor": platform.processor(),
            "architecture": list(platform.architecture()),
        },
        "distribution": {
            "name": os_release.get("NAME", ""),
            "version": os_release.get("VERSION", ""),
            "id": os_release.get("ID", ""),
            "pretty": os_release.get("PRETTY_NAME", ""),
        },
        "cpu": {
            "logical_cores": os.cpu_count(),
            "model": parse_cpu_model(),
        },
        "memory": {
            "total_bytes": meminfo.get("MemTotal", 0),
            "free_bytes": meminfo.get("MemFree", 0),
            "available_bytes": meminfo.get("MemAvailable", 0),
            "swap_total_bytes": meminfo.get("SwapTotal", 0),
            "swap_free_bytes": meminfo.get("SwapFree", 0),
        },
        "disk_root": {
            "total_bytes": disk.total,
            "used_bytes": disk.used,
            "free_bytes": disk.free,
        },
        "uptime": {
            "seconds": get_uptime_seconds(),
            "readable": seconds_to_dhms(get_uptime_seconds()),
        },
        "processes": {
            "count": count_processes(),
        },
        "python": {
            "version": sys.version,
            "executable": sys.executable,
        },
        "environment": {
            "SHELL": os.environ.get("SHELL", ""),
            "HOME": os.environ.get("HOME", ""),
            "USER": os.environ.get("USER", ""),
            "PATH": os.environ.get("PATH", ""),
            "LANG": os.environ.get("LANG", ""),
            "TZ": os.environ.get("TZ", ""),
        },
        "time": {
            "timezone": time.tzname,
            "unix_epoch": time.time(),
        },
    }

    return info


def main() -> None:
    info = gather_os_info()
    print(json.dumps(info, indent=2))


if __name__ == "__main__":
    main()