#!/usr/bin/env bash
# shellcheck disable=SC2010,SC1111

show-help() {
    echo "用法：$0 <install | uninstall> [选项...]"
    echo
    echo "可用操作："
    echo "  install             安装 DXVK"
    echo "  uninstall           卸载 DXVK"
    echo
    echo "可用选项："
    echo "  --without-dxgi      安装时不替换 dxgi.dll。"
    echo "  --with-d3d10        安装时替换 d3d10.dll 和 d3d10_1.dll。DXVK 版本 2.0 后不再支持。"
    echo "  --symlink           安装时将原文件替换为指向新文件的软链接，而不是直接复制新文件。"
}

ACTION="$1"
case "$ACTION" in
    install | uninstall)
        shift 1
        ;;
    -h | --help | '')
        show-help
        exit 1
        ;;
    *)
        if [[ $# -le 0 ]] || printf '%s\n' "$*" | grep -Eq -- '-h|--help'; then
            true
        else
            echo "未知操作或选项：$ACTION"
        fi
        show-help
        exit 2
        ;;
esac
printf '%s\n' "$*" | grep -Eq -- '-h|--help' && {
    show-help
    exit 1
}
with_dxgi=true
with_d3d10=false
use_symlink=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --without-dxgi)
            with_dxgi=false
            ;;
        --with-d3d10)
            with_d3d10=true
            ;;
        --symlink)
            use_symlink=true
            ;;
    esac
    shift 1
done

isemptydir() {
    [[ -z "$1" ]] && {
        echo 'isemptydir: 需要 1 个参数' >&2
        return 2
    }
    ! ls -A1q "$1" | grep -q .
}

COPY_FILE_CMDLINE=('cp' '-v' '--reflink=auto')
if $use_symlink; then
    COPY_FILE_CMDLINE=('ln' '-v' '-s')
fi

BASEDIR="$(
    cd "$(dirname "$0")" || exit
    pwd
)"

replacements_x86="x86"
if ! [[ -d "$BASEDIR/x86" ]]; then
    replacements_x86="x32"
fi
replacements_x64="x64"

# wineserver（虽然不会实际调用）
wineserver="$(which wineserver)"
if [[ -z "$wineserver" ]]; then
    echo '无法找到命令 wineserver 的路径。检查你的 WINE 运行环境安装情况。' >&2
    exit 1
elif ! "$wineserver" --version 2>&1 | grep -iFq 'wine'; then
    echo "$wineserver"'：不是 wineserver 可执行文件。检查你的 WINE 运行环境安装情况。' >&2
    exit 1
fi

# wine/wine64，必须与 wineserver 位于同一目录
wine="$(dirname "$wineserver")/wine"
# 优先查找 wine，其次是 wine64
if ! [[ -f "$wine" ]] || ! [[ -x "$wine" ]]; then
    wine="$(dirname "$wineserver")/wine64"
    if ! [[ -f "$wine" ]] || ! [[ -x "$wine" ]]; then
        echo '无法找到命令 wine 或 wine64 的路径。检查你的 WINE 运行环境安装情况。' >&2
        exit 1
    fi
fi
if ! "$wine" --version | grep -iFq 'wine-'; then
    echo "$wine"'：不是 wine 或 wine64 可执行文件。检查你的 WINE 运行环境安装情况。' >&2
    exit 1
fi

# 在运行 wine 之前首先判断 WINEPREFIX 是否有效以避免意外创建 WINEPREFIX
winepfx="${WINEPREFIX:="$HOME/.wine"}"
if ! [[ -d "$winepfx" ]] || ! [[ -f "$winepfx/system.reg" ]] || ! [[ -d "$winepfx/dosdevices" ]]; then
    echo "$winepfx"'：不是一个有效的 WINEPREFIX。' >&2
    exit 1
fi
export WINEPREFIX="$winepfx"

# 避免无用的调试信息刷屏
export WINEDEBUG=-all
# 禁用 mscoree 和 mshtml 以避免 wine 自动下载它们
export WINEDLLOVERRIDES="mscoree,mshtml="

# 确保要替换的源文件作为占位符存在
"$wine" wineboot -u

# c:\windows 目录的 UNIX 路径，移除末尾的 \r
winepfx_systemroot="$("$wine" winepath -u "$("$wine" cmd /c echo %SYSTEMROOT%)")"
winepfx_systemroot="${winepfx_systemroot/$'\r'/}"

# syswow64 存在且非空 == 支持混合架构（32 和 64 位）
# syswow64 存在但为空目录 == 仅支持 64 位
# syswow64 不存在 == 仅支持 32 位
# system32 不存在 == 无效的 WINEPREFIX
if [[ ! -d "$winepfx_systemroot/system32" ]] || isemptydir "$winepfx_systemroot/system32"; then
    echo "$WINEPREFIX"'：无法检测 WINEPREFIX 内 WoW64 子系统的状况。检查你的 WINEPREFIX 完整性。' >&2
    exit 1
fi
if [[ -d "$winepfx_systemroot/syswow64" ]]; then
    x64_dstdir="$winepfx_systemroot/system32"
    if isemptydir "$winepfx_systemroot/syswow64"; then
        x86_dstdir=''
    else
        x86_dstdir="$winepfx_systemroot/syswow64"
    fi
else
    x64_dstdir=''
    x86_dstdir="$winepfx_systemroot/system32"
fi

dll-override() {
    if ! "$wine" reg add 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v "$1" /d native /f >/dev/null 2>&1; then
        echo -e "添加函数库顶替 ${1} 失败。" >&2
        exit 1
    else
        echo -e "已将 ${1} 添加为函数库顶替。" >&2
    fi
}
dll-restore() {
    if ! "$wine" reg delete 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v "$1" /f >/dev/null 2>&1; then
        echo -e "移除函数库顶替 ${1} 失败。" >&2
        exit 1
    else
        echo -e "已将 ${1} 从函数库顶替中移除。" >&2
    fi
}
install-file() {
    srcfile="${BASEDIR}/${2}/${1}.dll"
    dstfile="${3}/${1}.dll"

    if [[ -f "${srcfile}.so" ]]; then
        srcfile="${srcfile}.so"
    fi

    if ! [[ -f "${srcfile}" ]]; then
        echo "${srcfile}: 未找到源文件。跳过。" >&2
        return 1
    fi

    if [[ -n "$3" ]]; then
        if [[ -f "${dstfile}" ]] || [[ -L "${dstfile}" ]]; then
            if ! [[ -f "${dstfile}.old" ]]; then
                mv -v "${dstfile}" "${dstfile}.old"
            else
                rm -v "${dstfile}"
            fi
            "${COPY_FILE_CMDLINE[@]}" "${srcfile}" "${dstfile}"
        else
            echo "${dstfile}: WINEPREFIX 中无此文件。" >&2
            return 1
        fi
    fi
    return 0
}
uninstall-file() {
    srcfile="${BASEDIR}/${2}/${1}.dll"
    dstfile="${3}/${1}.dll"

    if [[ -f "${srcfile}.so" ]]; then
        srcfile="${srcfile}.so"
    fi

    if ! [[ -f "${srcfile}" ]]; then
        echo "${srcfile}: 未找到源文件。跳过。" >&2
        return 1
    fi

    if ! [[ -f "${dstfile}" ]] && ! [[ -L "${dstfile}" ]]; then
        echo "${dstfile}: WINEPREFIX 中无此文件。" >&2
        return 1
    fi

    if [[ -f "${dstfile}.old" ]]; then
        rm -v "${dstfile}"
        mv -v "${dstfile}.old" "${dstfile}"
        return 0
    else
        return 1
    fi
}
install-dll() {
    x64_success=''
    x86_success=''
    if [[ -n "$x64_dstdir" ]]; then
        if install-file "$1" "$replacements_x64" "$x64_dstdir"; then
            x64_success=true
        fi
    else
        x64_success=true
    fi
    if [[ -n "$x86_dstdir" ]]; then
        if install-file "$1" "$replacements_x86" "$x86_dstdir"; then
            x86_success=true
        fi
    else
        x86_success=true
    fi
    if [[ -n "$x64_success" ]] && [[ -n "$x86_success" ]]; then
        dll-override "$1"
    fi
}
uninstall-dll() {
    x64_success=''
    x86_success=''
    if [[ -n "$x64_dstdir" ]]; then
        if uninstall-file "$1" "$replacements_x64" "$x64_dstdir"; then
            x64_success=true
        fi
    else
        x64_success=true
    fi
    if [[ -n "$x86_dstdir" ]]; then
        if uninstall-file "$1" "$replacements_x86" "$x86_dstdir"; then
            x86_success=true
        fi
    else
        x86_success=true
    fi
    if [[ -n "$x64_success" ]] && [[ -n "$x86_success" ]]; then
        dll-restore "$1"
    fi
}

operation="${ACTION}-dll"

"$operation" d3d9
"$operation" d3d10core
"$operation" d3d11
if "$with_dxgi"; then
    "$operation" dxgi
fi
if "$with_d3d10"; then
    "$operation" d3d10
    "$operation" d3d10_1
fi
